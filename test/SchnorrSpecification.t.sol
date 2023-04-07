pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSchnorr} from "src/libs/LibSchnorr.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";
import {LibScribeECCRef} from "./utils/LibScribeECCRef.sol";

/**
 * @notice Schnorr Signature Scheme Specifications
 */
contract SchnorrSpecification is Test {
    // forgefmt: disable-start
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    /*//////////////////////////////////////////////////////////////
                       SCRIBE SCHNORR SIGNATURES
    //////////////////////////////////////////////////////////////*/
    /*
    Signing Specification:
    ---------------------

    Let Q be the order of secp256k1
    Let G be the generator of secp256k1

    Let k ∊ [1, Q) be the nonce
    Let message be a bytes32 value, unequal to zero

    Let signer be the signing key pair, i.e. signer = {pubKey: {x: uint, y: uint}, privKey: uint}

    Step 1:
        Compute commitment point `R` via:
            R = [k]G

    Step 2:
        Construct commitment `Rₑ` via:
            Rₑ = R.toAddress()

    Step 3:
        Construct challenge `e` via:
            e = keccak256(abi.encodePacked(
                    signer.pubKey.x,
                    uint8(signer.pubKey.yParity())
                    message,
                    R.toAddress()
                ) (mod Q)

    Step 4:
        Compute signature `s` via:
            s = k - (e * signer.privKey)       (mod Q)
              = k + (Q - (e * signer.privKey)) (mod Q)


    Key Aggregation Specification:
    -----------------------------

    Let the signers' public keys be:
        signers = [pubKey1, pubKey2, ..., pubKeyN]

    Let the aggregated public key be:
        aggPubKey = sum(signers)
                  = pubKey1 + pubKey2 + ... + pubKeyN
                  = [privKey1]G + [privKey2]G + ... + [privKeyN]G
                  = [privKey1 + privKey2 + ... + privKeyN]G

    Note that this aggregation scheme is vulnerable to rogue-key attacks.
    However, the Scribe contract verifies that each participating public key
    owns their corresponding private key, preventing rogue-key attacks.
    Reference: [MuSig2, page 2](https://eprint.iacr.org/2020/1261.pdf)


    Signature Aggregation Specification:
    -----------------------------------

    Let ss be the signers' computed, as defined in Step 4, signatures:
        ss = [s1, s2, ..., sN]

    Let the aggregated signature be:
        aggS = sum(ss)            (mod Q)
             = s1 + s2 + ... + sN (mod Q)
             = k1 - (e * privKey1) + k2 - (e * privKey2) + ... + kN - (e * privKeyN)
             = (k1 + k2 + ... + kN) - (e * (privKey1 + privKey2 + ... + privKeyN))
    */

    function test_SchnorrSpecification_SingleSigning(
        bytes32 message,
        uint signerPrivKey,
        uint k
    ) public {
        // Message is not zero.
        vm.assume(message != bytes32(0));

        // signerPrivKey ∊ [1, Q).
        vm.assume(signerPrivKey > 0);
        vm.assume(signerPrivKey < LibSecp256k1.Q());

        // k ∊ [1, Q).
        vm.assume(k > 0);
        vm.assume(k < LibSecp256k1.Q());

        // Preparation: Make signer struct
        LibHelpers.Feed memory signer = LibHelpers.Feed({
            privKey: signerPrivKey,
            pubKey: LibScribeECCRef.scalarMultiplication(signerPrivKey)
        });

        // Step 1: Compute commitment point R.
        LibSecp256k1.Point memory R = LibScribeECCRef.scalarMultiplication(k);

        // Step 2: Construct commitment Rₑ.
        address R_e = R.toAddress();

        // Step 3: Construct challenge e.
        uint e = uint(keccak256(abi.encodePacked(
            signer.pubKey.x,
            uint8(signer.pubKey.yParity()),
            message,
            R_e
        )));
        e %= LibSecp256k1.Q();

        // Step 4: Compute signature s.
        uint s = addmod(
            k ,
            LibSecp256k1.Q() - mulmod(e, signer.privKey, LibSecp256k1.Q()),
            LibSecp256k1.Q()
        );

        // Perform signature verification.
        bool ok = LibSchnorr.verifySignature(
            signer.pubKey,
            message,
            bytes32(s),
            R_e
        );
        assertTrue(ok);
    }

    mapping(uint => bool) signerPrivKeyFilter;

    function test_SchnorrSpecification_MultipleSigning(
        bytes32 message,
        uint[] memory signerPrivKeys,
        uint[] memory ks
    ) public {
        // Message is not zero.
        vm.assume(message != bytes32(0));

        // Set length of signerPrivKeys and ks to 5.
        // Note that this is foundry/solidity specific and has nothing to do with
        // the spec.
        vm.assume(signerPrivKeys.length > 5);
        vm.assume(ks.length > 5);
        assembly ("memory-safe") {
            mstore(signerPrivKeys, 5)
            mstore(ks, 5)
        }

        // Each signing privKey ∊ [1, Q).
        // Each signing privKey is unique.
        for (uint i; i < signerPrivKeys.length; i++) {
            vm.assume(signerPrivKeys[i] > 0);
            vm.assume(signerPrivKeys[i] < LibSecp256k1.Q());

            vm.assume(!signerPrivKeyFilter[signerPrivKeys[i]]);
            signerPrivKeyFilter[signerPrivKeys[i]] = true;
        }

        // Each k ∊ [1, Q).
        for (uint i; i < ks.length; i++) {
            vm.assume(ks[i] > 0);
            vm.assume(ks[i] < LibSecp256k1.Q());
        }

        // Preparations: Make signer structs.
        LibHelpers.Feed[] memory signers = new LibHelpers.Feed[](signerPrivKeys.length);
        for (uint i; i < signers.length; i++) {
            signers[i] = LibHelpers.Feed({
                privKey: signerPrivKeys[i],
                pubKey: LibScribeECCRef.scalarMultiplication(signerPrivKeys[i])
            });
        }

        // Preparations: Aggregate nonces.
        //
        // Note that the aggregation of the nonces is _not_ defined via this
        // specification.
        //
        // Aggregate nonces via: k = sum(ks) (mod Q)
        uint k;
        for (uint i; i < ks.length; i++) {
            k = addmod(k, ks[i], LibSecp256k1.Q());
        }

        // Step 0: Aggregate signers' public keys.
        //
        // This step MUST happen before Step 3.
        LibSecp256k1.JacobianPoint memory aggPubKeyAsJac = signers[0].pubKey.toJacobian();
        for (uint i = 1; i < signers.length; i++) {
            aggPubKeyAsJac.addAffinePoint(signers[i].pubKey);
        }

        // Step 1: Compute commitment point R.
        LibSecp256k1.Point memory R = LibScribeECCRef.scalarMultiplication(k);

        // Step 2: Construct commitment Rₑ.
        address R_e = R.toAddress();

        // Step 3: Construct challenge e.
        uint e = uint(keccak256(abi.encodePacked(
            aggPubKeyAsJac.toAffine().x,
            uint8(aggPubKeyAsJac.toAffine().yParity()),
            message,
            R_e
        )));
        e %= LibSecp256k1.Q();

        // Step 4: Compute signature s.
        //
        // First we compute the signatures for each signer as defined in Step 4...
        uint[] memory ss = new uint[](signers.length);
        for (uint i; i < ss.length; i++) {
            ss[i] = addmod(
                ks[i],
                LibSecp256k1.Q() - mulmod(e, signers[i].privKey, LibSecp256k1.Q()),
                LibSecp256k1.Q()
            );
        }
        // ...Afterwards we aggregate the signatures as defined in
        // "Signature Aggregation Specification".
        uint aggS;
        for (uint i; i < ss.length; i++) {
            aggS = addmod(aggS, ss[i], LibSecp256k1.Q());
        }

        // Perform signature verification.
        bool ok = LibSchnorr.verifySignature(
            aggPubKeyAsJac.toAffine(),
            message,
            bytes32(aggS),
            R_e
        );
        assertTrue(ok);
    }

    /*//////////////////////////////////////////////////////////////
                       BIP-340 SCHNORR SIGNATURES
    //////////////////////////////////////////////////////////////*/
    /*
    Signing Specification:
    ---------------------

    Let Q be the order of secp256k1
    Let G be the generator of secp256k1

    Let k ∊ [1, Q) be the nonce
    Let message be a bytes32 value, unequal to zero

    Let signer be the signing key pair, i.e. signer = {pubKey: {x: uint, y: uint}, privKey: uint}

    Step 1:
        Compute commitment point `R` via:
            R = [k]G

    Step 2:
        Construct challenge `e` via:
            e = sha256(abi.encodePacked(                        (Note usage of sha256 as hash function)
                    sha256("BIP0340/challenge"),                (Note to include tag 2 times)
                    sha256("BIP0340/challenge"),
                    R.x,
                    signer.pubKey.x,
                    message,
                ) (mod Q)

    Step 3:
        Compute signature `s` via:
            s = k + (e * signer.privKey) (mod Q)


    Key Aggregation Specification:
    -----------------------------

    Let the signers' public keys be:
        signers = [pubKey1, pubKey2, ..., pubKeyN]

    Let the aggregated public key be:
        aggPubKey = sum(signers)
                  = pubKey1 + pubKey2 + ... + pubKeyN
                  = [privKey1]G + [privKey2]G + ... + [privKeyN]G
                  = [privKey1 + privKey2 + ... + privKeyN]G

    Note that this aggregation scheme is vulnerable to rogue-key attacks.
    However, the Scribe contract verifies that each participating public key
    owns their corresponding private key, preventing rogue-key attacks.
    Reference: [MuSig2, page 2](https://eprint.iacr.org/2020/1261.pdf)


    Signature Aggregation Specification:
    -----------------------------------

    Let ss be the signers' computed, as defined in Step 4, signatures:
        ss = [s1, s2, ..., sN]

    Let the aggregated signature be:
        aggS = sum(ss)            (mod Q)
             = s1 + s2 + ... + sN (mod Q)
             = k1 - (e * privKey1) + k2 - (e * privKey2) + ... + kN - (e * privKeyN)
             = (k1 + k2 + ... + kN) - (e * (privKey1 + privKey2 + ... + privKeyN))
    */

    function test_BIP340_SchnorrSpecification_SingleSigning(
        bytes32 message,
        uint signerPrivKey,
        uint k
    ) public {
        // Message is not zero.
        vm.assume(message != bytes32(0));

        // signerPrivKey ∊ [1, Q).
        vm.assume(signerPrivKey > 0);
        vm.assume(signerPrivKey < LibSecp256k1.Q());

        // k ∊ [1, Q).
        vm.assume(k > 0);
        vm.assume(k < LibSecp256k1.Q());

        // Preparation: Make signer struct
        LibHelpers.Feed memory signer = LibHelpers.Feed({
            privKey: signerPrivKey,
            pubKey: LibScribeECCRef.scalarMultiplication(signerPrivKey)
        });

        // Step 1: Compute commitment point R.
        LibSecp256k1.Point memory R = LibScribeECCRef.scalarMultiplication(k);

        // Step 2: Construct challenge e.
        uint e = uint(sha256(abi.encodePacked(
            sha256("BIP0340/challenge"),
            sha256("BIP0340/challenge"),
            R.x,
            signer.pubKey.x,
            message
        )));
        e %= LibSecp256k1.Q();

        // Step 3: Compute signature s.
        uint s = addmod(
            k ,
            mulmod(e, signer.privKey, LibSecp256k1.Q()),
            LibSecp256k1.Q()
        );

        // Perform signature verification.
        bool ok = LibSchnorr.verifySignatureBIP340(
            signer.pubKey,
            R,
            message,
            bytes32(s)
        );
        assertTrue(ok);
    }

    function test_BIP340_SchnorrSpecification_MultipleSigning(
        bytes32 message,
        uint[] memory signerPrivKeys,
        uint[] memory ks
    ) public {
        // Message is not zero.
        vm.assume(message != bytes32(0));

        // Set length of signerPrivKeys and ks to 5.
        // Note that this is foundry/solidity specific and has nothing to do with
        // the spec.
        vm.assume(signerPrivKeys.length > 5);
        vm.assume(ks.length > 5);
        assembly ("memory-safe") {
            mstore(signerPrivKeys, 5)
            mstore(ks, 5)
        }

        // Each signing privKey ∊ [1, Q).
        // Each signing privKey is unique.
        for (uint i; i < signerPrivKeys.length; i++) {
            vm.assume(signerPrivKeys[i] > 0);
            vm.assume(signerPrivKeys[i] < LibSecp256k1.Q());

            vm.assume(!signerPrivKeyFilter[signerPrivKeys[i]]);
            signerPrivKeyFilter[signerPrivKeys[i]] = true;
        }

        // Each k ∊ [1, Q).
        for (uint i; i < ks.length; i++) {
            vm.assume(ks[i] > 0);
            vm.assume(ks[i] < LibSecp256k1.Q());
        }

        // Preparations: Make signer structs.
        LibHelpers.Feed[] memory signers = new LibHelpers.Feed[](signerPrivKeys.length);
        for (uint i; i < signers.length; i++) {
            signers[i] = LibHelpers.Feed({
                privKey: signerPrivKeys[i],
                pubKey: LibScribeECCRef.scalarMultiplication(signerPrivKeys[i])
            });
        }

        // Preparations: Aggregate nonces.
        //
        // Note that the aggregation of the nonces is _not_ defined via this
        // specification.
        //
        // Aggregate nonces via: k = sum(ks) (mod Q)
        uint k;
        for (uint i; i < ks.length; i++) {
            k = addmod(k, ks[i], LibSecp256k1.Q());
        }

        // Step 0: Aggregate signers' public keys.
        //
        // This step MUST happen before Step 3.
        LibSecp256k1.JacobianPoint memory aggPubKeyAsJac = signers[0].pubKey.toJacobian();
        for (uint i = 1; i < signers.length; i++) {
            aggPubKeyAsJac.addAffinePoint(signers[i].pubKey);
        }

        // Step 1: Compute commitment point R.
        LibSecp256k1.Point memory R = LibScribeECCRef.scalarMultiplication(k);

        // Step 2: Construct challenge e.
        uint e = uint(sha256(abi.encodePacked(
            sha256("BIP0340/challenge"),
            sha256("BIP0340/challenge"),
            R.x,
            aggPubKeyAsJac.toAffine().x,
            message
        )));
        e %= LibSecp256k1.Q();

        // Step 3: Compute signature s.
        // TODO
        //
        // First we compute the signatures for each signer as defined in Step 3...
        uint[] memory ss = new uint[](signers.length);
        for (uint i; i < ss.length; i++) {
            ss[i] = addmod(
                ks[i] ,
                mulmod(e, signers[i].privKey, LibSecp256k1.Q()),
                LibSecp256k1.Q()
            );
        }
        // ...Afterwards we aggregate the signatures as defined in
        // "Signature Aggregation Specification".
        uint aggS;
        for (uint i; i < ss.length; i++) {
            aggS = addmod(aggS, ss[i], LibSecp256k1.Q());
        }

        // Perform signature verification.
        bool ok = LibSchnorr.verifySignatureBIP340(
            aggPubKeyAsJac.toAffine(),
            R,
            message,
            bytes32(aggS)
        );
        assertTrue(ok);
    }

    // forgefmt: disable-end
}
