// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";

import {IScribe} from "../../src/IScribe.sol";

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

/**
 * @title ScribeOffboarder
 *
 * @notice Permanently disables a `Scribe` oracle in a single transaction.
 *         The contract must be granted `auth` on the target scribe.
 *
 *         `offboard(scribe, feedIds, pokeAge, sig, commitment)` drops every
 *         currently-lifted feed, sets bar = 1, lifts the hardcoded
 *         offboarder feed, pokes val = 0, and drops the offboarder feed
 *         again. The caller supplies the list of lifted feed ids and a
 *         pre-computed Schnorr signature — pair it with the
 *         `computeOffboardArgs(scribe)` view, which enumerates the feeds
 *         and signs off-chain via eth_call.
 *
 * @dev Security note: the offboarder feed's private key is hardcoded as a
 *      `constant` in the bytecode and is therefore publicly readable. This
 *      is intentional; the feed is only lifted inside an offboarder call
 *      and dropped again before the transaction returns, so any signatures
 *      craftable from the leaked key require the attacker to already hold
 *      `auth` on the scribe and re-lift the feed (at which point they could
 *      poke arbitrary values directly anyway).
 */
contract ScribeOffboarder is Auth {
    // -----------------------------------------------------------------------------
    // Hardcoded Offboarder Feed
    //
    // All four values below are derived from a single string seed:
    //
    //     SEED         = "Chronicle.ScribeOffboarder.v1"
    //     FEED_PRIV_KEY = uint(keccak256(SEED)) mod Q
    //     pubKey       = vm.createWallet(FEED_PRIV_KEY).{publicKeyX, publicKeyY}
    //     ECDSA(v,r,s) = vm.sign(FEED_PRIV_KEY, FEED_REGISTRATION_MESSAGE)
    //
    //     where Q is the order of secp256k1 and
    //
    //     FEED_REGISTRATION_MESSAGE =
    //         keccak256(
    //             "\x19Ethereum Signed Message:\n32" ‖
    //             keccak256("Chronicle Feed Registration")
    //         )
    //
    // FEED_REGISTRATION_MESSAGE is a Scribe protocol constant (see
    // `Scribe.feedRegistrationMessage`), so the ECDSA signature below is
    // valid against every Scribe deployment.
    //
    // To regenerate / verify these values, run:
    //
    //     forge script script/PrintFeedConstants.s.sol -vvv

    /// @dev `keccak256("Chronicle.ScribeOffboarder.v1") mod Q`.
    uint internal constant FEED_PRIV_KEY =
        0xf067ac0350b6ab5e39cf9138ae16508404c05af8b58676e07ae14e9a510a600e;

    uint private constant FEED_PUBKEY_X =
        0xc2f3bfebb984817bbcaaf2b8e185259b09493f6db4b2c30d7b4feca89f7a64b2;

    uint private constant FEED_PUBKEY_Y =
        0x53a0dc54c1d22a62fbb1b3724737486c7e61c26080a44817eef7f5992a521a40;

    /// @notice Feed id is the highest-order byte of the ethereum address
    ///         derived from the offboarder feed's public key
    ///         (= 0x03da1Db2b7875106395548682B068a7C7b296902 => id = 0x03).
    uint8 public constant feedId = 0x03;

    // ECDSA signature over FEED_REGISTRATION_MESSAGE by FEED_PRIV_KEY.
    uint8 private constant LIFT_V = 28;
    bytes32 private constant LIFT_R =
        0xc9988947c96dd6899cc097e3979b1e4d9228e09b4bc7cf53a9e0fe2ff395a77c;
    bytes32 private constant LIFT_S =
        0x76ec989c8765878f18daceb7893ea2c24b1a87401c847e240a1301c3565f8dd7;

    // -----------------------------------------------------------------------------
    // secp256k1 Constants

    /// @dev x-coordinate of the secp256k1 generator G.
    uint private constant G_X =
        0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;

    /// @dev Order of the secp256k1 group.
    uint private constant Q =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /// @dev `v` value corresponding to G (G_y is even, so parity = 0).
    uint8 private constant G_V = 27;

    // -----------------------------------------------------------------------------
    // Other Constants

    /// @dev `computeOffboardArgs` defaults `pokeAge` to
    ///      `block.timestamp - POKE_AGE_BACKDATE`. Picked so the helper's
    ///      eth_call result remains usable for ~5 minutes of off-chain
    ///      signing + tx-submission latency, while still being safely
    ///      older than `block.timestamp` at execution time.
    uint32 private constant POKE_AGE_BACKDATE = 5 minutes;

    // -----------------------------------------------------------------------------
    // Events

    event Offboarded(address indexed caller, address indexed scribe);

    // -----------------------------------------------------------------------------
    // Constructor

    constructor(address initialAuthed) Auth(initialAuthed) {}

    // -----------------------------------------------------------------------------
    // Offboard

    /// @notice Offboards `scribe` using pre-computed inputs. Produce the
    ///         arguments off-chain by eth_calling
    ///         `computeOffboardArgs(scribe)`.
    /// @dev `feedIds` must include every currently-lifted feed on `scribe`
    ///      (a missing id would leave that feed lifted after the call).
    ///      Extra / already-dropped ids are harmless — scribe's `drop` is
    ///      idempotent per id.
    function offboard(
        address scribe,
        uint8[] calldata feedIds,
        uint32 pokeAge,
        bytes32 signature,
        address commitment
    ) external auth {
        _offboard(scribe, feedIds, pokeAge, signature, commitment);
    }

    /// @notice Returns everything `offboard` needs: the list of
    ///         currently-lifted feed ids on `scribe`, a `pokeAge`
    ///         (backdated by ~5 minutes for submission latency), and a
    ///         1-of-1 Schnorr signature over
    ///         `constructPokeMessage({val: 0, age: pokeAge})`.
    ///
    ///         Intended to be eth_called — running it on-chain costs the
    ///         ~1.1M gas that `scribe.feeds()` charges, which is the whole
    ///         point of splitting the pre-computation off-chain.
    function computeOffboardArgs(address scribe)
        external
        view
        returns (
            uint8[] memory feedIds,
            uint32 pokeAge,
            bytes32 signature,
            address commitment
        )
    {
        feedIds = _enumerateFeedIds(IScribe(scribe));
        pokeAge = uint32(block.timestamp - POKE_AGE_BACKDATE);
        (signature, commitment) = _schnorrSigFor(scribe, pokeAge);
    }

    // -----------------------------------------------------------------------------
    // Internal — offboard sequence

    function _offboard(
        address scribe,
        uint8[] calldata feedIds,
        uint32 pokeAge,
        bytes32 schnorrSignature,
        address schnorrCommitment
    ) internal {
        require(scribe != address(0), "ScribeOffboarder: scribe=zero");
        IScribe target = IScribe(scribe);

        if (feedIds.length != 0) {
            target.drop(feedIds);
        }
        target.setBar(1);
        _liftOffboarderFeed(target);

        target.poke(
            IScribe.PokeData({val: 0, age: pokeAge}),
            IScribe.SchnorrData({
                signature: schnorrSignature,
                commitment: schnorrCommitment,
                feedIds: abi.encodePacked(feedId)
            })
        );

        target.drop(feedId);

        // Note that we don't re-call `setBar(1)` — scribe rejects
        // `setBar(0)` with `require(bar_ != 0)`, and bar is already 1 from
        // the earlier call. With no feeds lifted, no future poke can verify
        // regardless.

        emit Offboarded(msg.sender, scribe);
    }

    /// @dev Reads every feed currently lifted on `target` and returns their
    ///      ids. `scribe.feeds()` is the expensive part — 256 slot reads.
    function _enumerateFeedIds(IScribe target)
        internal
        view
        returns (uint8[] memory)
    {
        address[] memory currentFeeds = target.feeds();
        uint8[] memory ids = new uint8[](currentFeeds.length);
        for (uint i; i < currentFeeds.length; i++) {
            ids[i] = uint8(uint(uint160(currentFeeds[i])) >> 152);
        }
        return ids;
    }

    function _liftOffboarderFeed(IScribe target) internal {
        target.lift(
            LibSecp256k1.Point({x: FEED_PUBKEY_X, y: FEED_PUBKEY_Y}),
            IScribe.ECDSAData({v: LIFT_V, r: LIFT_R, s: LIFT_S})
        );
    }

    function _schnorrSigFor(address scribe, uint32 pokeAge)
        internal
        view
        returns (bytes32 signature, address commitment)
    {
        bytes32 message = IScribe(scribe)
            .constructPokeMessage(IScribe.PokeData({val: 0, age: pokeAge}));
        return _signSchnorr(message);
    }

    // -----------------------------------------------------------------------------
    // Internal — Schnorr signing

    /// @dev Produces a 1-of-1 Schnorr signature over `message` using the
    ///      hardcoded offboarder feed.
    ///
    ///      The ethereum address `R_e = address(k·G)` is computed via the
    ///      ecrecover precompile trick rather than a full secp256k1 scalar
    ///      multiplication: with `h = 0`, `r = G_x`, `v = G_v`,
    ///      `s = k·G_x mod Q`, ecrecover returns exactly `address(k·G)` —
    ///      which is all the signing scheme needs as the commitment.
    ///
    ///      See the scribe repo's `docs/Schnorr.md` for the scheme this
    ///      implements.
    function _signSchnorr(bytes32 message)
        internal
        pure
        returns (bytes32 signature, address commitment)
    {
        // k = H(privKey ‖ m) mod Q
        uint nonce =
            uint(keccak256(abi.encodePacked(FEED_PRIV_KEY, message))) % Q;

        // R_e = address(k·G)  via the ecrecover trick.
        commitment = ecrecover(
            bytes32(0), G_V, bytes32(G_X), bytes32(mulmod(nonce, G_X, Q))
        );
        require(commitment != address(0), "ScribeOffboarder: bad commitment");

        // e = H(Pₓ ‖ Pₚ ‖ m ‖ R_e) mod Q
        uint challenge = uint(
            keccak256(
                abi.encodePacked(
                    FEED_PUBKEY_X, uint8(FEED_PUBKEY_Y & 1), message, commitment
                )
            )
        ) % Q;

        // s = k + e·x mod Q
        signature =
            bytes32(addmod(nonce, mulmod(challenge, FEED_PRIV_KEY, Q), Q));
    }
}
