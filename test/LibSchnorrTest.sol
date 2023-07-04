pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSchnorr} from "src/libs/LibSchnorr.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSchnorrExtended} from "script/libs/LibSchnorrExtended.sol";
import {LibSecp256k1Extended} from "script/libs/LibSecp256k1Extended.sol";
import {LibDissig} from "script/libs/LibDissig.sol";
import {LibOracleSuite} from "script/libs/LibOracleSuite.sol";

abstract contract LibSchnorrTest is Test {
    using LibSchnorrExtended for uint;
    using LibSchnorrExtended for uint[];
    using LibSchnorrExtended for LibSecp256k1.Point;
    using LibSchnorrExtended for LibSecp256k1.Point[];
    using LibSecp256k1Extended for uint;

    // @todo Remove when dissig also works. Otherwise nice way to debug.
    function test_OracleSuiteError() public {
        // Fuzzing input.
        bytes32 message =
            0x6661696c65640000000000000000000000000000000000000000000000000000;
        uint[] memory privKeys = new uint[](3);
        privKeys[0] = 21900;
        privKeys[1] = 16990;
        privKeys[2] =
            30049578511147215784808879450479972380521167567270003804066285409374367121408;

        // Make list of public key.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            pubKeys[i] = privKeys[i].derivePublicKey();
        }

        // Sign via Oracle Suite.
        uint signature;
        address commitment;
        (signature, commitment) = LibOracleSuite.sign(privKeys, message);

        // Sign via LibSchnorrExtended.
        uint wantSignature;
        address wantCommitment;
        (wantSignature, wantCommitment) =
            LibSchnorrExtended.signMessage(privKeys, message);

        if (wantSignature != signature) {
            console2.log("Signatures differ!");
        }
        if (wantCommitment != commitment) {
            console2.log("Commitments differ!");
        }

        // Verify Oracle Suite's signature is ok.
        bool ok = LibSchnorr.verifySignature(
            pubKeys.aggregatePublicKeys(),
            message,
            bytes32(signature),
            commitment
        );
        assertTrue(ok);

        // -- Sign message via LibSchnorrExtended "manually" to print debug info
        console2.log("");
        console2.log("");
        {
            // 1. Collect list of pubKeys of signers.
            LibSecp256k1.Point[] memory pubKeys =
                new LibSecp256k1.Point[](privKeys.length);
            for (uint i; i < privKeys.length; i++) {
                pubKeys[i] = privKeys[i].derivePublicKey();
            }

            // 2. Compute aggPubKey.
            LibSecp256k1.Point memory aggPubKey;
            aggPubKey = LibSchnorrExtended.aggregatePublicKeys(pubKeys);
            console2.log("AggPubKey:");
            console2.log("  - x", aggPubKey.x);
            console2.log("  - y", aggPubKey.y);
            console2.log("");

            // 3. Collect list of noncePubKeys from signers.
            LibSecp256k1.Point[] memory noncePubKeys =
                new LibSecp256k1.Point[](privKeys.length);
            for (uint i; i < privKeys.length; i++) {
                // 3.1. Derive secure nonce.
                uint nonce =
                    LibSchnorrExtended.deriveNonce(privKeys[i], message);
                console2.log("Nonce", nonce);

                // 3.2. Compute noncePubKey and append to list of noncePubKeys.
                noncePubKeys[i] =
                    LibSchnorrExtended.computeNoncePublicKey(nonce);
            }
            console2.log("");

            // 4. Compute aggNoncePubKey.
            LibSecp256k1.Point memory aggNoncePubKey;
            aggNoncePubKey =
                LibSchnorrExtended.aggregatePublicKeys(noncePubKeys);

            // 5. Derive commitment from aggNoncePubKey.
            address commitment =
                LibSchnorrExtended.deriveCommitment(aggNoncePubKey);
            console2.log("Commitment", commitment);

            // 6. Construct challenge.
            bytes32 challenge = LibSchnorrExtended.constructChallenge(
                aggPubKey, message, commitment
            );
            console2.log("Challenge", uint(challenge));
        }
    }

    function testFuzzDifferentialOracleSuite_verifySignature(
        uint[] memory privKeySeeds,
        bytes32 message
    ) public {
        vm.assume(privKeySeeds.length > 1);
        // Keep number of signers low to not run out-of-gas.
        if (privKeySeeds.length > 50) {
            assembly ("memory-safe") {
                mstore(privKeySeeds, 50)
            }
        }

        // Let each privKey ∊ [2, Q).
        // Note that we allow double signing.
        uint[] memory privKeys = new uint[](privKeySeeds.length);
        for (uint i; i < privKeySeeds.length; i++) {
            privKeys[i] = bound(privKeySeeds[i], 2, LibSecp256k1.Q() - 1);
        }

        // Make list of public key.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](privKeySeeds.length);
        for (uint i; i < privKeySeeds.length; i++) {
            pubKeys[i] = privKeys[i].derivePublicKey();
        }

        // Compute aggregated public key.
        LibSecp256k1.Point memory aggPubKey = pubKeys.aggregatePublicKeys();

        // IMPORTANT: Don't do anything if pubKey.x is zero.
        if (aggPubKey.x == 0) {
            console2.log("Received public key with zero x coordinate");
            console2.log("-- Public key's y coordinate", aggPubKey.y);
            return;
        }

        // Create signature via oracle-suite.
        uint signature;
        address commitment;
        (signature, commitment) = LibOracleSuite.sign(privKeys, message);

        // IMPORTANT: Don't do anything if signature is invalid.
        if (signature == 0) {
            console2.log("Signature is zero");
            return;
        }

        // Expect oracle-suite's signature to be verifiable.
        bool ok = LibSchnorr.verifySignature(
            aggPubKey, message, bytes32(signature), commitment
        );
        assertTrue(ok);
    }

    function testFuzzDifferentialDissig_verifySignature() public {}

    function testFuzz_verifySignature_SingleSigner(
        uint privKeySeed,
        bytes32 message
    ) public {
        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Compute pubKey.
        LibSecp256k1.Point memory pubKey = privKey.derivePublicKey();

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Signature is _not_ verifiable if one of the following cases hold:
        // - commitment == address(0)
        // - pubKey.x == 0
        // - signature == 0
        // - signature >= Q
        bool shouldBeOk = true;
        if (commitment == address(0)) shouldBeOk = false;
        if (pubKey.x == 0) shouldBeOk = false;
        if (signature == 0) shouldBeOk = false;
        if (signature >= LibSecp256k1.Q()) shouldBeOk = false;

        // Signature verification should equal expected value.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertEq(ok, shouldBeOk);
    }

    function testFuzz_verifySignature_MultipleSigners(
        uint[] memory privKeySeeds,
        bytes32 message
    ) public {
        vm.assume(privKeySeeds.length > 1);
        // Keep low to not run out-of-gas.
        vm.assume(privKeySeeds.length < 50);

        // Let each privKey ∊ [2, Q).
        // Note that we allow double signing.
        uint[] memory privKeys = new uint[](privKeySeeds.length);
        for (uint i; i < privKeySeeds.length; i++) {
            privKeys[i] = bound(privKeySeeds[i], 2, LibSecp256k1.Q() - 1);
        }

        // Make list of public key.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](privKeySeeds.length);
        for (uint i; i < privKeySeeds.length; i++) {
            pubKeys[i] = privKeys[i].derivePublicKey();
        }

        // Compute aggregated public key.
        LibSecp256k1.Point memory aggPubKey = pubKeys.aggregatePublicKeys();

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKeys.signMessage(message);

        // Signature is _not_ verifiable if one of the following cases hold:
        // - commitment == address(0)
        // - pubKey.x == 0
        // - signature == 0
        // - signature >= Q
        bool shouldBeOk = true;
        if (commitment == address(0)) shouldBeOk = false;
        if (aggPubKey.x == 0) shouldBeOk = false;
        if (signature == 0) shouldBeOk = false;
        if (signature >= LibSecp256k1.Q()) shouldBeOk = false;

        // Signature verification should equal expected value.
        bool ok = LibSchnorr.verifySignature(
            pubKeys.aggregatePublicKeys(),
            message,
            bytes32(signature),
            commitment
        );
        assertEq(ok, shouldBeOk);
    }

    function testFuzz_verifySignature_FailsIf_SignatureMutated(
        uint privKeySeed,
        bytes32 message,
        uint signatureMask
    ) public {
        vm.assume(signatureMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Mutate signature.
        signature ^= signatureMask;

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }

    function testFuzz_verifySignature_FailsIf_CommitmentMutated(
        uint privKeySeed,
        bytes32 message,
        uint160 commitmentMask
    ) public {
        vm.assume(commitmentMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Mutate commitment.
        commitment = address(uint160(commitment) ^ commitmentMask);

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }

    function testFuzz_verifySignature_FailsIf_MessageMutated(
        uint privKeySeed,
        bytes32 message,
        uint messageMask
    ) public {
        vm.assume(messageMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Mutate message.
        message = bytes32(uint(message) ^ messageMask);

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }

    function testFuzz_verifySignature_FailsIf_PubKeyMutated(
        uint privKeySeed,
        bytes32 message,
        uint pubKeyXMask,
        bool flipParity
    ) public {
        vm.assume(pubKeyXMask != 0 || flipParity);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Compute and mutate pubKey.
        LibSecp256k1.Point memory pubKey = privKey.derivePublicKey();
        pubKey.x = pubKey.x ^ pubKeyXMask;
        pubKey.y = flipParity ? pubKey.y + 1 : pubKey.y;

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            pubKey, message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }
}
