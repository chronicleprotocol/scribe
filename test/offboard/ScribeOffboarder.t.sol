// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test, Vm} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "../../src/IScribe.sol";
import {Scribe} from "../../src/Scribe.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

import {ScribeOffboarder} from "../../script/offboard/ScribeOffboarder.sol";

contract ScribeOffboarderTest is Test {
    bytes32 internal constant WAT = bytes32("ETH/USD");

    /// @dev Must match `feedId` in `ScribeOffboarder.sol`.
    uint8 internal constant OFFBOARDER_FEED_ID = 0x03;

    Scribe internal scribe;
    ScribeOffboarder internal offboarder;

    function setUp() public {
        scribe = new Scribe({initialAuthed: address(this), wat_: WAT});
        IToll(address(scribe)).kiss(address(this));

        offboarder = new ScribeOffboarder({initialAuthed: address(this)});
        IAuth(address(scribe)).rely(address(offboarder));

        vm.warp(1_700_000_000);
    }

    // -----------------------------------------------------------------------------
    // Pre-signed offboard (computeSchnorrSig + offboard(scribe, pokeAge, sig, com))

    function test_offboard() public {
        _liftRandomFeeds(3, 0xBEEF);

        (
            uint8[] memory feedIds,
            uint32 pokeAge,
            bytes32 sig,
            address commitment
        ) = offboarder.computeOffboardArgs(address(scribe));

        offboarder.offboard(address(scribe), feedIds, pokeAge, sig, commitment);

        assertEq(scribe.feeds().length, 0);
        assertEq(scribe.bar(), type(uint8).max);
        (bool ok,) = scribe.tryRead();
        assertFalse(ok);
    }

    function testFuzz_offboard(
        uint8 nFeeds,
        uint64 timeAdvance,
        uint64 seedSalt
    ) public {
        nFeeds = uint8(bound(nFeeds, 0, 32));
        timeAdvance = uint64(bound(timeAdvance, 1, 365 days));

        _liftRandomFeeds(nFeeds, uint(seedSalt) | 1);
        vm.warp(block.timestamp + timeAdvance);

        (
            uint8[] memory feedIds,
            uint32 pokeAge,
            bytes32 sig,
            address commitment
        ) = offboarder.computeOffboardArgs(address(scribe));

        offboarder.offboard(address(scribe), feedIds, pokeAge, sig, commitment);

        assertEq(scribe.feeds().length, 0);
        assertEq(scribe.bar(), type(uint8).max);
        (bool ok,) = scribe.tryRead();
        assertFalse(ok);

        assertTrue(scribe.authed(address(offboarder)));
    }

    // -----------------------------------------------------------------------------
    // Auth Protection

    function testFuzz_offboard_presigned_isAuthProtected(address caller)
        public
    {
        vm.assume(!IAuth(address(offboarder)).authed(caller));

        (
            uint8[] memory feedIds,
            uint32 pokeAge,
            bytes32 sig,
            address commitment
        ) = offboarder.computeOffboardArgs(address(scribe));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAuth.NotAuthorized.selector, caller)
        );
        offboarder.offboard(address(scribe), feedIds, pokeAge, sig, commitment);
    }

    // -----------------------------------------------------------------------------
    // Value zeroing

    function testFuzz_offboard_zeroesValue(uint8 nFeeds, uint64 seedSalt)
        public
    {
        nFeeds = uint8(bound(nFeeds, 0, 32));
        _liftRandomFeeds(nFeeds, uint(seedSalt) | 1);

        (uint8[] memory feedIds, uint32 pokeAge, bytes32 sig, address com) =
            offboarder.computeOffboardArgs(address(scribe));
        offboarder.offboard(address(scribe), feedIds, pokeAge, sig, com);

        (bool ok, uint val) = scribe.tryRead();
        assertFalse(ok, "tryRead should report invalid");
        assertEq(val, 0, "scribe stored value must be zero");

        vm.expectRevert();
        scribe.read();
    }

    // -----------------------------------------------------------------------------
    // Helpers

    function _feedId(address who) internal pure returns (uint8) {
        return uint8(uint(uint160(who)) >> 152);
    }

    /// @dev Lifts up to `n` feeds derived from sequential private keys
    ///      starting at `seed`. Skips collisions with already-lifted feed
    ///      ids and with the offboarder's reserved id.
    function _liftRandomFeeds(uint8 n, uint seed)
        internal
        returns (uint lifted)
    {
        if (n == 0) {
            return 0;
        }

        bytes32 reg = scribe.feedRegistrationMessage();

        uint bloom;
        bloom |= 1 << OFFBOARDER_FEED_ID; // reserve

        uint pk = seed;
        uint tried;
        while (lifted < n && tried < 1024) {
            tried++;
            Vm.Wallet memory w = vm.createWallet(pk++);
            uint8 id = _feedId(w.addr);

            if (bloom & (1 << id) != 0) {
                continue;
            }
            bloom |= 1 << id;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(w.privateKey, reg);
            scribe.lift(
                LibSecp256k1.Point({x: w.publicKeyX, y: w.publicKeyY}),
                IScribe.ECDSAData({v: v, r: r, s: s})
            );
            lifted++;
        }
    }
}
