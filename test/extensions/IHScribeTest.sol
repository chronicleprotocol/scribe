// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";

import {IHScribe} from "src/extensions/IHScribe.sol";
import {HScribe} from "src/extensions/HScribe.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

import {IScribeTest} from "../IScribeTest.sol";

abstract contract IHScribeTest is IScribeTest {
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    IHScribe private hscribe;

    function setUp(address scribe_) internal override(IScribeTest) {
        super.setUp(scribe_);

        hscribe = IHScribe(scribe_);
    }

    // -- Test: Deployment --

    function test_Deployment() public override(IScribeTest) {
        super.test_Deployment();

        // History's size set to 10.
        assertEq(hscribe.historySize(), 10);

        // Historical read functions all fail or return zero.
        for (uint8 i; i < 10; i++) {
            _checkHRead_FailsIf_HistoricalDataDoesNotExist(uint8(i));
        }
    }

    function test_Deployment_FailsIf_HistorySizeZero() public {
        vm.expectRevert();
        new HScribe(address(this), bytes32("ETH/USD"), 0);
    }

    // -- Test: History Buffer --

    function test_MultipleFullHistoryCycles() public {
        LibFeed.Feed[] memory feeds = _liftFeeds(hscribe.bar());

        // Cache history size.
        uint historySize = hscribe.historySize();

        // Perform 2x history size many pokes and verify after each that current
        // and all historical values are correct.
        //
        // Note to manually keep track of block.timestamp as solc may remove
        // block.timestamp calls inside a loop.
        uint32 timestamp = uint32(block.timestamp);
        IScribe.PokeData memory pokeData;
        IScribe.SchnorrData memory schnorrData;
        for (uint i; i < historySize * 2; i++) {
            uint128 val = uint128(i) + 1;

            pokeData = IScribe.PokeData(val, timestamp);
            schnorrData = feeds.signSchnorr(hscribe.constructPokeMessage(pokeData));

            hscribe.poke(pokeData, schnorrData);

            // Verify read functions invariant.
            _checkHRead_ZeroInvariant();

            // Verify historical values.
            for (uint j; j <= historySize && j <= i; j++) {
                uint8 past = uint8(j);
                uint wantVal = val - j;
                uint wantAge = timestamp - j;

                // Note to expect h-read functions to fail for non-existing
                // historical requests.
                if (j <= i) {
                    _checkHRead(past, wantVal, wantAge);
                } else {
                    _checkHRead_FailsIf_HistoricalDataDoesNotExist(past);
                }
            }

            vm.warp(++timestamp);
        }

        // Verify historical read out of bounds fails.
        _checkHRead_FailsIf_OutOfBounds(uint8(historySize + 1));
    }

    // -- Test: Toll Protected Functions --

    function test_hRead_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        hscribe.hRead(0);
    }

    function test_hTryRead_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        hscribe.hTryRead(0);
    }

    function test_hReadWithAge_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        hscribe.hReadWithAge(0);
    }

    function test_hTryReadWithAge_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        hscribe.hTryReadWithAge(0);
    }

    // -- Internal Helpers --

    function _checkHRead_ZeroInvariant() internal {
        bool ok1;
        bool ok2;
        uint val1;
        uint val2;
        uint age1;
        uint age2;

        // Verify read() == hRead(0).
        val1 = hscribe.read();
        val2 = hscribe.hRead(0);
        assertEq(val1, val2);

        // Verify tryRead() == tryRead(0).
        (ok1, val1) = hscribe.tryRead();
        (ok2, val2) = hscribe.hTryRead(0);
        assertEq(ok1, ok2);
        assertEq(val1, val2);

        // Verify readWithAge() == hReadWithAge(0).
        (val1, age1) = hscribe.readWithAge();
        (val2, age2) = hscribe.hReadWithAge(0);
        assertEq(val1, val2);
        assertEq(age1, age2);

        // Verify tryReadWithAge() == hTryReadWithAge(0).
        (ok1, val1, age1) = hscribe.tryReadWithAge();
        (ok2, val2, age2) = hscribe.hTryReadWithAge(0);
        assertEq(ok1, ok2);
        assertEq(val1, val2);
        assertEq(age1, age2);
    }

    function _checkHRead(uint8 past, uint wantVal, uint wantAge) internal {
        bool ok;
        uint val;
        uint age;

        // Check hRead(past)(uint).
        val = hscribe.hRead(past);
        assertEq(val, wantVal);

        // Check hTryRead(past)(bool,uint).
        (ok, val) = hscribe.hTryRead(past);
        assertTrue(ok);
        assertEq(val, wantVal);

        // Check hReadWithAge(past)(uint,uint).
        (val, age) = hscribe.hReadWithAge(past);
        assertEq(val, wantVal);
        assertEq(age, wantAge);

        // Check hTryReadWithAge(past)(bool,uint,uint).
        (ok, val, age) = hscribe.hTryReadWithAge(past);
        assertTrue(ok);
        assertEq(val, wantVal);
        assertEq(age, wantAge);
    }

    function _checkHRead_FailsIf_HistoricalDataDoesNotExist(uint8 past) internal {
        bool ok;
        uint val;
        uint age;

        // Check hRead(past)(uint) fails.
        try hscribe.hRead(past) returns (uint) {
            assertTrue(false);
        } catch {}

        // Check hTryRead(past)(bool,uint) fails.
        (ok, val) = hscribe.hTryRead(past);
        assertFalse(ok);
        assertEq(val, 0);

        // Check hReadWithAge(past)(uint,uint) fails.
        try hscribe.hReadWithAge(past) returns (uint, uint) {
            assertTrue(false);
        } catch {}

        // Check hTryReadWithAge(past)(bool,uint,uint) fails.
        (ok, val, age) = hscribe.hTryReadWithAge(past);
        assertFalse(ok);
        assertEq(val, 0);
        assertEq(age, 0);
    }

    function _checkHRead_FailsIf_OutOfBounds(uint8 past) internal {
        // Check hRead(past)(uint) fails.
        try hscribe.hRead(past) returns (uint) {
            assertTrue(false);
        } catch {}

        // Check hTryRead(past)(bool,uint) reverts.
        try hscribe.hTryRead(past) returns (bool, uint) {
            assertTrue(false);
        } catch {}

        // Check hReadWithAge(past)(uint,uint) fails.
        try hscribe.hReadWithAge(past) returns (uint, uint) {
            assertTrue(false);
        } catch {}

        // Check hTryReadWithAge(past)(bool,uint,uint) reverts.
        try hscribe.hTryReadWithAge(past) returns (bool, uint, uint) {
            assertTrue(false);
        } catch {}
    }
}

