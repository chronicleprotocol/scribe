pragma solidity ^0.8.16;

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibDissig} from "./LibDissig.sol";
// @audit MUST not use LibDissig, but LibSecp256k1Extended.
//        This allows to have 100% solidity based system.
//        The go backend can be differential tests against this
//        implementation.

/**
 * @title LibSchnorrExtended
 *
 * @notice Extended library for Schnorr signatures as specified in `Schnorr.md`
 */
library LibSchnorrExtended {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibDissig for uint;

    /// @dev Returns a Schnorr signature of type (signature, commitment) signing
    ///      `message` via `privKey`.
    function signMessage(uint privKey, bytes32 message)
        internal
        returns (uint, address)
    {
        LibSecp256k1.Point memory pubKey = privKey.toPoint();

        // 1. Select secure nonce.
        uint nonce = deriveNonce(privKey, message);

        // 2. Compute noncePubKey.
        LibSecp256k1.Point memory noncePubKey = computeNoncePublicKey(nonce);

        // 3. Derive commitment from noncePubKey.
        address commitment = deriveCommitment(noncePubKey);

        // 4. Construct challenge.
        bytes32 challenge = constructChallenge(pubKey, message, commitment);

        // 5. Compute signature.
        uint signature = computeSignature(privKey, nonce, challenge);

        // => The public key signs the message via the signature and
        //    commitment.
        return (signature, commitment);
    }

    /// @dev Returns a Schnorr multi-signature (aggregated signature) of type
    ///      (signature, commitment) signing `message` via `privKeys`.
    function signMessage(uint[] memory privKeys, bytes32 message)
        internal
        returns (uint, address)
    {
        // 1. Collect list of pubKeys of signers.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            pubKeys[i] = privKeys[i].toPoint();
        }

        // 2. Compute aggPubKey.
        LibSecp256k1.Point memory aggPubKey = aggregatePublicKeys(pubKeys);

        // 3. Collect list of noncePubKeys from signers.
        LibSecp256k1.Point[] memory noncePubKeys =
            new LibSecp256k1.Point[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            // 3.1. Select secure nonce.
            uint nonce = deriveNonce(privKeys[i], message);

            // 3.2. Compute noncePubKey and append to list of noncePubKeys.
            noncePubKeys[i] = computeNoncePublicKey(nonce);
        }

        // 4. Compute aggNoncePubKey.
        LibSecp256k1.Point memory aggNoncePubKey;
        aggNoncePubKey = aggregatePublicKeys(noncePubKeys);

        // 5. Derive commitment from aggNoncePubKey.
        address commitment = deriveCommitment(aggNoncePubKey);

        // 6. Construct challenge.
        bytes32 challenge = constructChallenge(aggPubKey, message, commitment);

        // 7. Collect signatures from signers.
        uint[] memory signatures = new uint[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            uint nonce = deriveNonce(privKeys[i], message);

            signatures[i] = computeSignature(privKeys[i], nonce, challenge);
        }

        // 8. Compute aggSignature.
        uint aggSignature;
        for (uint i; i < privKeys.length; i++) {
            // Note to keep aggSignature ∊ [0, Q).
            aggSignature = addmod(aggSignature, signatures[i], LibSecp256k1.Q());
        }

        // => The aggregated public key signs the message via the aggregated
        //    signature and commitment.
        return (aggSignature, commitment);
    }

    function verifySignature(
        LibSecp256k1.Point memory pubKey,
        bytes32 message,
        bytes32 signature,
        address commitment
    ) internal pure returns (bool) {
        if (commitment == address(0) || signature == 0) {
            return false;
        }

        uint challenge = uint(constructChallenge(pubKey, message, commitment));

        // Compute msgHash = -sig * Pₓ      (mod Q)
        //                 = Q - (sig * Pₓ) (mod Q)
        uint msgHash = LibSecp256k1.Q()
            - mulmod(uint(signature), pubKey.x, LibSecp256k1.Q());

        // Compute v = Pₚ + 27
        uint v = pubKey.yParity() + 27;

        // Set r = Pₓ
        uint r = pubKey.x;

        // Compute s = e * Pₓ (mod Q)
        uint s = mulmod(challenge, pubKey.x, LibSecp256k1.Q());

        // Perform ecrecover call.
        // Note to perform necessary castings.
        address recovered =
            ecrecover(bytes32(msgHash), uint8(v), bytes32(r), bytes32(s));

        // Verification succeeds if the ecrecover'ed address equals Rₑ, i.e.
        // the commitment.
        return commitment == recovered;
    }

    /*//////////////////////////////////////////////////////////////
                          LOW-LEVEL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deriveNonce(uint privKey, bytes32 message)
        internal
        pure
        returns (uint)
    {
        return uint(keccak256(abi.encodePacked(privKey, message)));
    }

    function computeNoncePublicKey(uint nonce)
        internal
        returns (LibSecp256k1.Point memory)
    {
        // R = [k]G
        return nonce.toPoint();
    }

    function deriveCommitment(LibSecp256k1.Point memory noncePubKey)
        internal
        pure
        returns (address)
    {
        return noncePubKey.toAddress();
    }

    function aggregatePublicKeys(LibSecp256k1.Point[] memory pubKeys)
        internal
        pure
        returns (LibSecp256k1.Point memory)
    {
        require(pubKeys.length != 0);

        // Let aggPubKey be the sum of already processed public keys.
        // Note the switch to Jacobian coordinates.
        LibSecp256k1.JacobianPoint memory aggPubKey = pubKeys[0].toJacobian();

        for (uint i = 1; i < pubKeys.length; i++) {
            // Write result directly into aggPubKey memory.
            aggPubKey.addAffinePoint(pubKeys[i]);
        }

        // Return in Affine coordinates.
        return aggPubKey.toAffine();
    }

    function constructChallenge(
        LibSecp256k1.Point memory pubKey,
        bytes32 message,
        address commitment
    ) internal pure returns (bytes32) {
        // Construct challenge = H(Pₓ ‖ Pₚ ‖ m ‖ Rₑ) mod Q
        // @todo Challenge here differently created than in spec.
        return bytes32(
            uint(
                keccak256(
                    abi.encodePacked(
                        pubKey.x, uint8(pubKey.yParity()), message, commitment
                    )
                )
            ) % LibSecp256k1.Q()
        );
    }

    function computeSignature(uint privKey, uint nonce, bytes32 challenge)
        internal
        pure
        returns (uint)
    {
        // s = k - (e * x)       (mod Q)
        //   = k + (Q - (e * x)) (mod Q)
        // forgefmt: disable-next-item
        return addmod(
            nonce,
            LibSecp256k1.Q() - mulmod(uint(challenge), privKey, LibSecp256k1.Q()),
            LibSecp256k1.Q()
        );
    }
}
