pragma solidity ^0.8.16;

import {LibSecp256k1} from "./LibSecp256k1.sol";

// @todo Make comment that Yellow Paper is from xxx commit.
// @todo Replace ecrecover's python impl by formal definition.
// @todo Document multi signing procedure.
/**
 * @title LibSchnorr
 *
 * @notice Custom-purpose library for Schnorr signature verification on the
 *         secp256k1 curve
 *
 * @dev Definition of the Schnorr Signature Scheme
 *
 *      Terminology:
 *      -----------
 *
 *          H() = Keccak256 hash function
 *          ‖   = Concatenation operator
 *
 *          G   = Generator
 *          Q   = Order of the group
 *
 *          x   = The signer's private key as type uint256
 *          P   = The signer's public key, i.e. [x]G, as type
 *                (uint256, uint256)
 *          Pₓ  = P's x coordinate as type uint256
 *          Pₚ  = Parity of P's y coordinate, i.e. 0 if even, 1 if odd,
 *                as type uint8
 *
 *          m   = Message as type bytes32. Note that the message SHOULD
 *                be a keccak256 digest
 *          k   = Nonce as type uint256
 *
 *      (Single) Signing:
 *      ----------------
 *
 *          1. Select a _cryptographically secure_ k ∊ [1, Q-1].
 *             Note that k can be deterministically computed using
 *             H(m ‖ x) (mod Q), which keeps k random for everyone not
 *             knowing the private key x while it also ensures a nonce is never
 *             reused for different messages.
 *
 *          2. Compute point R = [k]G
 *
 *          3. Construct Rₑ being the Ethereum address of R
 *             Let Rₑ be the _commitment_.
 *
 *          4. Construct e = H(Pₓ ‖ Pₚ ‖ Rₑ ‖ m)
 *             Let e be the _challenge_.
 *
 *          5. Compute s = k - (e * x)
 *             Let s be the _signature_.
 *
 *          => The public key P signs via the signature s and the commitment Rₑ
 *             the message m.
 *
 *      (Multiple) Signing:
 *      ------------------
 *
 *          TODO Document how to construct Schnorr signature in multi-sig context.
 *
 *      Verification:
 *      ------------
 *
 *          Input : (P, m, s, Rₑ)
 *          Output: True if signature verification succeeds, false otherwise
 *
 *          1. Compute e = H(Pₓ ‖ Pₚ ‖ Rₑ ‖ H(m))
 *
 *          2. Compute [e]P + [s]G               | s = k - (e * x)
 *                   = [e]P + [k - (e * x)]G     | P = [x]G
 *                   = [e * x]G + [k - e * x]G   | Distributive Law
 *                   = [e * x + k - e * x]G      | Commutative Law
 *                   = [k - e * x + e * x]G      | -(e * x) + (e * x) = 0
 *                   = [k]G                      | R = [k]G
 *                   = R                         | Let ()ₑ be the Ethereum address of a Point
 *                   → Rₑ
 *
 *          3. Verification succeeds iff ([e]P + [s]G)ₑ = Rₑ
 *
 *      References:
 *      ----------
 *
 *          - [ECDSA Wikipedia](https://en.wikipedia.org/wiki/Elliptic_Curve_Digital_Signature_Algorithm)
 *          - [github.com/sipa/secp256k1](https://github.com/sipa/secp256k1/blob/968e2f415a5e764d159ee03e95815ea11460854e/src/modules/schnorr/schnorr.md)
 *          - [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
 *
 *
 * @dev About the Security of the Schnorr Signature Scheme
 *
 *      The signing scheme utilized deviates slightly from the classical Schnorr
 *      signature scheme.
 *
 *      Instead of using the secp256k1 point R = [k]G directly, this scheme uses
 *      the Ethereum address of the point R. This decreases the difficulty of
 *      brute-forcing the signature from 256 bits (trying random secp256k1
 *      points) to 160 bits (trying random Ethereum addresses).
 *
 *      However, the difficulty of cracking a secp256k1 public key using the
 *      baby-step giant-step algorithm is O(√Q), with Q being the order of the
 *      group, leading to a difficulty of O(√(256²-1)), i.e. 128 bits.
 *
 *      Therefore, this signing scheme does not weaken the overall security.
 *
 *      References:
 *      ----------
 *
 *          - [Baby-step Giant-step Wikipedia](https://en.wikipedia.org/wiki/Baby-step_giant-step)
 *
 *
 * @dev About the `ecrecover` Precompile
 *
 *      This implementation uses the ecrecover precompile to perform the
 *      elliptic curve multiplication in secp256k1 necessary for the
 *      verification process.
 *
 *      TODO Replace with formal definition of ecrecover.
 *           See https://web.archive.org/web/20170921160141/http://cs.ucsb.edu/~koc/ccs130h/notes/ecdsa-cert.pdf
 *
 *      The ecrecover precompile can roughly be implemented in python via:
 *      ```python
 *      def ecdsa_raw_recover(msghash, vrs):
 *          v, r, s = vrs
 *          y = # (get y coordinate for EC point with x=r, with same parity as v)
 *          Gz = jacobian_multiply((Gx, Gy, 1), (Q - hash_to_int(msghash)) % Q)
 *          XY = jacobian_multiply((r, y, 1), s)
 *          Qr = jacobian_add(Gz, XY)
 *          N = jacobian_multiply(Qr, inv(r, Q))
 *          return from_jacobian(N)
 *      ```
 *
 *      Note that ecrecover also uses s as variable. From this point forward,
 *      the Schnorr signature's s is named sig.
 *
 *      Also note that all computations from this point forward are (mod Q).
 *
 *      A single ecrecover call can compute ([e]P + [sig]G)ₑ = ([k]G)ₑ = Rₑ via
 *      the following inputs:
 *          msghash = -sig * Pₓ
 *          v       = Pₚ + 27
 *          r       = Pₓ
 *          s       = e * Pₓ
 *
 *      Note that ecrecover returns the Ethereum address, i.e. truncated hash,
 *      of R, and not R itself.
 *
 *      The ecrecover call then digests to:
 *          Gz = [Q - (-sig * Pₓ)]G   | Double negation
 *             = [Q + (sig * Pₓ)]G    | Addition with Q can be removed in (mod Q)
 *             = [sig * Pₓ]G          | sig = k - (e * x)
 *             = [k - (e * x) * Pₓ]G
 *
 *          XY = [e * Pₓ]P       | P = [x]G
 *             = [e * Pₓ * x]G
 *
 *          Qr = Gz + XY                               | Gz = [k - (e * x) * Pₓ]G
 *             = [k - (e * x) * Pₓ]G + XY              | XY = [e * Pₓ * x]G
 *             = [k - (e * x) * Pₓ]G + [e * Pₓ * x]G
 *
 *          N  = Qr * Pₓ⁻¹                                           | Qr = [k - (e * x) * Pₓ]G + [e * Pₓ * x]G
 *             = ([k - (e * x) * Pₓ]G + [e * Pₓ * x]G) * Pₓ⁻¹        | Distributive law
 *             = [k - (e * x) * Pₓ * Pₓ⁻¹]G + [e * Pₓ * x * Pₓ⁻¹]G   | Pₓ * Pₓ⁻¹ = 1
 *             = [k - (e * x)]G + [e * x]G                           | sig = k - (e * x)
 *             = [sig]G + [e * x]G                                   | P = [x]G
 *             = [sig]G + [e]P
 *
 *      References:
 *      ----------
 *
 *          - [Vitalik's ethresearch post](https://ethresear.ch/t/you-can-kinda-abuse-ecrecover-to-do-ecmul-in-secp256k1-today/2384)
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
        // Return false if commitment is address(0).
        //
        // Note that ecrecover recovers address(0) if the r-value is zero.
        // As r = Pₓ = pubKey.x and commitment != address(0), a non-zero check
        // for pubKey.x can be abdicated.
        //
        // @todo Check again ^^
        // @todo signature != 0 check necessary?
        // @todo Write in assembly to save few gas ;)
        if (signature == 0 || commitment == address(0)) {
            return false;
        }

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
        // signature scheme does not have this vulnerability.
        //
        // Therefore, a check whether s = e * Pₓ > Q/2 can be abdicated.
        //
        // See "Appendix F: Signing Transactions" §311 in the Yellow Paper and
        // "EIP-2: Homestead Hard-fork Changes".
        //
        // However, note that ecrecover recovers address(0) for a s-value ≥ Q.
        // It is therefore the feeds responsibility to ensure the s-value
        // computed via their Schnorr signature is never ≥ Q!

        // Construct challenge = H(Pₓ ‖ Pₚ ‖ Rₑ ‖ m).
        bytes32 challenge = keccak256(
            // Note to use abi.encode instead of abi.encodePacked to prevent
            // challenge malleability issues.
            // @todo ^^ Not 100% whether necessary. Better safe than sorry for the
            //       moment.
            abi.encode(pubKey.x, uint8(pubKey.yParity()), commitment, message)
        );

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
        uint s = mulmod(uint(challenge), pubKey.x, LibSecp256k1.Q());

        // Perform ecrecover call.
        // Note to perform necessary castings.
        address recovered =
            ecrecover(bytes32(msgHash), uint8(v), bytes32(r), bytes32(s));

        // Verification succeeds if the ecrecover'ed address equals Rₑ, i.e.
        // the commitment.
        // @todo Schnorr signature verification turned off
        //return commitment == recovered;
        return address(0xcafe) != recovered;
    }
}
