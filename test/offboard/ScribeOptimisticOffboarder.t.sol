// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test, Vm} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "../../src/IScribe.sol";
import {IScribeOptimistic} from "../../src/IScribeOptimistic.sol";
import {ScribeOptimistic} from "../../src/ScribeOptimistic.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

import {
    ScribeOptimisticOffboarder
} from "../../script/offboard/ScribeOptimisticOffboarder.sol";

contract ScribeOptimisticOffboarderTest is Test {
    bytes32 internal constant WAT = bytes32("ETH/USD");

    /// @dev Must match `feedId` in `ScribeOptimisticOffboarder.sol`.
    uint8 internal constant OFFBOARDER_FEED_ID = 0x03;

    ScribeOptimistic internal scribe;
    ScribeOptimisticOffboarder internal offboarder;

    function setUp() public {
        scribe = new ScribeOptimistic({initialAuthed: address(this), wat_: WAT});
        IToll(address(scribe)).kiss(address(this));

        offboarder =
            new ScribeOptimisticOffboarder({initialAuthed: address(this)});
        IAuth(address(scribe)).rely(address(offboarder));

        vm.warp(1_700_000_000);
    }

    // -----------------------------------------------------------------------------
    // Offboard

    function test_offboard() public {
        _liftRandomFeeds(3, 0xBEEF);

        offboarder.offboard_Step1(address(scribe));
        vm.warp(block.timestamp + 1);
        offboarder.offboard_Step2(address(scribe));

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

        offboarder.offboard_Step1(address(scribe));
        vm.warp(block.timestamp + timeAdvance);
        offboarder.offboard_Step2(address(scribe));

        assertEq(scribe.feeds().length, 0);
        assertEq(scribe.bar(), type(uint8).max);
        (bool ok,) = scribe.tryRead();
        assertFalse(ok);

        assertFalse(IAuth(address(scribe)).authed(address(offboarder)));
    }

    // -----------------------------------------------------------------------------
    // Step 1

    function testFuzz_offboard_Step1_DropsFeedsAndSetsBarToOne(
        uint8 nFeeds,
        uint64 seedSalt
    ) public {
        nFeeds = uint8(bound(nFeeds, 0, 32));
        _liftRandomFeeds(nFeeds, uint(seedSalt) | 1);

        offboarder.offboard_Step1(address(scribe));

        // Note that no feed is lifted, ie no poke can verify.
        assertEq(scribe.feeds().length, 0);
        assertEq(scribe.bar(), 1);
        assertTrue(IAuth(address(scribe)).authed(address(offboarder)));
    }

    // -----------------------------------------------------------------------------
    // Step 2

    function test_offboard_Step2_FailsIf_Step1NotExecuted() public {
        _liftRandomFeeds(3, 0xBEEF);

        vm.expectRevert();
        offboarder.offboard_Step2(address(scribe));
    }

    function test_offboard_Step2_FailsIf_BarNotOne() public {
        offboarder.offboard_Step1(address(scribe));
        scribe.setBar(2);
        vm.warp(block.timestamp + 1);

        vm.expectRevert();
        offboarder.offboard_Step2(address(scribe));
    }

    function test_offboard_Step2_FailsIf_SameTimestampAsStep1() public {
        _liftRandomFeeds(3, 0xBEEF);

        offboarder.offboard_Step1(address(scribe));

        uint32 age = uint32(block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(IScribe.StaleMessage.selector, age, age)
        );
        offboarder.offboard_Step2(address(scribe));
    }

    // -----------------------------------------------------------------------------
    // Auth Protection

    function testFuzz_offboard_Step1_isAuthProtected(address caller) public {
        vm.assume(!IAuth(address(offboarder)).authed(caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAuth.NotAuthorized.selector, caller)
        );
        offboarder.offboard_Step1(address(scribe));
    }

    function testFuzz_offboard_Step2_isAuthProtected(address caller) public {
        vm.assume(!IAuth(address(offboarder)).authed(caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAuth.NotAuthorized.selector, caller)
        );
        offboarder.offboard_Step2(address(scribe));
    }

    // -----------------------------------------------------------------------------
    // Value zeroing

    function testFuzz_offboard_zeroesValue(uint8 nFeeds, uint64 seedSalt)
        public
    {
        nFeeds = uint8(bound(nFeeds, 0, 32));
        _liftRandomFeeds(nFeeds, uint(seedSalt) | 1);

        offboarder.offboard_Step1(address(scribe));
        vm.warp(block.timestamp + 1);
        offboarder.offboard_Step2(address(scribe));

        (bool ok, uint val) = scribe.tryRead();
        assertFalse(ok, "tryRead should report invalid");
        assertEq(val, 0, "scribe stored value must be zero");

        vm.expectRevert();
        scribe.read();
    }

    function test_offboard_zeroesValue_If_OpPokeFinalized() public {
        _opPoke(1e18);
        vm.warp(block.timestamp + scribe.opChallengePeriod());

        uint val = scribe.read();
        assertEq(val, 1e18);

        offboarder.offboard_Step1(address(scribe));
        vm.warp(block.timestamp + 1);
        offboarder.offboard_Step2(address(scribe));

        (bool ok, uint val_) = scribe.tryRead();
        assertFalse(ok);
        assertEq(val_, 0);
    }

    function test_offboard_zeroesValue_If_OpPokeNotFinalized() public {
        _opPoke(1e18);

        offboarder.offboard_Step1(address(scribe));
        vm.warp(block.timestamp + scribe.opChallengePeriod());
        offboarder.offboard_Step2(address(scribe));

        (bool ok, uint val) = scribe.tryRead();
        assertFalse(ok);
        assertEq(val, 0);
    }

    // -----------------------------------------------------------------------------
    // Helpers

    function _feedId(address who) internal pure returns (uint8) {
        return uint8(uint(uint160(who)) >> 152);
    }

    /// @dev Lifts a feed and opPokes `val` with an invalid Schnorr signature.
    function _opPoke(uint128 val) internal {
        Vm.Wallet memory w = vm.createWallet(0xC0FFEE);
        require(_feedId(w.addr) != OFFBOARDER_FEED_ID);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(w.privateKey, scribe.feedRegistrationMessage());
        scribe.lift(
            LibSecp256k1.Point({x: w.publicKeyX, y: w.publicKeyY}),
            IScribe.ECDSAData({v: v, r: r, s: s})
        );

        IScribe.PokeData memory pokeData =
            IScribe.PokeData({val: val, age: uint32(block.timestamp)});
        IScribe.SchnorrData memory schnorrData = IScribe.SchnorrData({
            signature: bytes32(0), commitment: address(0), feedIds: hex""
        });

        (v, r, s) = vm.sign(
            w.privateKey, scribe.constructOpPokeMessage(pokeData, schnorrData)
        );
        IScribeOptimistic(address(scribe))
            .opPoke(
                pokeData, schnorrData, IScribe.ECDSAData({v: v, r: r, s: s})
            );
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
