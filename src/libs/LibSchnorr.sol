pragma solidity ^0.8.16;

import {LibSecp256k1} from "./LibSecp256k1.sol";

/**
 * @title LibSchnorr
 *
 * @notice Custom-purpose library for Schnorr signature verification on the
 *         secp256k1 curve
 *
 * @dev References to the Ethereum Yellow Paper are based on the following
 *      version: "BERLIN VERSION beacfbd – 2022-10-24".
 */
library LibSchnorr {
    using LibSecp256k1 for LibSecp256k1.Point;

    // @todo Invariant: Uses constant gas
    /// @dev Returns false if commitment is address(0).
    /// @dev Returns false if pubKey.x is zero.
    /// @dev Expects message to not be zero.
    ///      Note that message SHOULD be a keccak256 digest.
    ///
    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Does not run into an infinite loop.
    function verifySignature(
        LibSecp256k1.Point memory pubKey,
        bytes32 message,
        bytes32 signature,
        address commitment
    ) internal pure returns (bool) {
        // Return false if commitment is address(0) or signature is trivial.
        //
        // Note that ecrecover recovers address(0) if the r-value is zero.
        // As r = Pₓ = pubKey.x and commitment != address(0), a non-zero check
        // for pubKey.x can be abdicated.
        if (commitment == address(0) || signature == 0) {
            return false;
        }

        // @todo This two paragraphs contradict each other?
        // Note that signatures must be less than Q to prevent signature
        // malleability. However, this check is disabled because the Scribe
        // contracts only accept messages with strictly monotonically
        // increasing timestamps, circumventing replay attack vectors and
        // therefore also signature malleability issues at a higher level.
        //
        // Note that this check MUST be enabled for general purpose Schnorr
        // signature verifications!
        //
        // if (uint(signature) >= LibSecp256k1.Q()) {
        //     return false;
        // }

        // Note that since EIP-2, all transactions whose s-value is greater than
        // Q/2 are considered invalid in order to protect against ECDSA's
        // signature malleability vulnerability. However, this does _not_ apply
        // to the ecrecover precompile! Note further, that the Schnorr
        // signature scheme does not have this malleability issue.
        //
        // Therefore, a check whether ecrecover's s-value = e * Pₓ > Q/2 can be
        // abdicated.
        //
        // See "Appendix F: Signing Transactions" §311 in the Yellow Paper and
        // "EIP-2: Homestead Hard-fork Changes".
        //
        // However, note that ecrecover returns address(0) for a s-value ≥ Q.
        // It is therefore the callers responsibility to ensure the s-value
        // computed via their Schnorr signature is not ≥ Q!

        // Construct challenge = H(Pₓ ‖ Pₚ ‖ m ‖ Rₑ) mod Q
        // @todo Challenge here different created than in spec.
        uint challenge = uint(
            keccak256(
                abi.encodePacked(
                    pubKey.x, uint8(pubKey.yParity()), message, commitment
                )
            )
        ) % LibSecp256k1.Q();

        // Compute msgHash = -sig * Pₓ      (mod Q)
        //                 = Q - (sig * Pₓ) (mod Q)
        //
        // Unchecked because the only protected operation performed is the
        // subtraction from Q where the subtrahend is the result of a (mod Q)
        // computation, i.e. the subtrahend is guaranteed to be less than Q.
        uint msgHash;
        unchecked {
            msgHash = LibSecp256k1.Q()
                - mulmod(uint(signature), pubKey.x, LibSecp256k1.Q());
        }

        // Compute v = Pₚ + 27
        //
        // Unchecked because pubKey.yParity() ∊ {0, 1} which cannot overflow
        // by adding 27.
        uint v;
        unchecked {
            v = pubKey.yParity() + 27;
        }

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
        // @todo Schnorr signature verification turned off
        return commitment == recovered;
    }

    /*//////////////////////////////////////////////////////////////
                                BIP-340
    //////////////////////////////////////////////////////////////*/

    function verifySignatureBIP340(
        LibSecp256k1.Point memory pubKey,
        LibSecp256k1.Point memory commitment,
        bytes32 message,
        bytes32 signature
    ) internal pure returns (bool) {
        // sha256("BIP0340/challenge");
        bytes32 tag = sha256("BIP0340/challenge");

        bytes32 challenge = bytes32(
            uint(
                sha256(
                    abi.encodePacked(tag, tag, commitment.x, pubKey.x, message)
                )
            ) % LibSecp256k1.Q()
        );

        bytes32 msgHash = bytes32(
            LibSecp256k1.Q()
                - mulmod(uint(signature), pubKey.x, LibSecp256k1.Q())
        );

        bytes32 s = bytes32(
            LibSecp256k1.Q()
                - mulmod(uint(challenge), pubKey.x, LibSecp256k1.Q())
        );

        address recovered = ecrecover(
            msgHash, uint8(pubKey.yParity() + 27), bytes32(pubKey.x), s
        );

        return recovered == commitment.toAddress();
    }
}
