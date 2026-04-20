// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {ScribeZeroValue} from "script/offboarder/ScribeZeroValue.sol";

contract ScribeZeroValueTest is Test {
    ScribeZeroValue private scribe;

    function setUp() public {
        scribe = new ScribeZeroValue();
    }

    function test_read() public {
        vm.expectRevert();
        scribe.read();
    }

    function test_tryRead() public {
        bool ok;
        uint val;
        (ok, val) = scribe.tryRead();
        assertFalse(ok);
        assertEq(val, 0);
    }

    function test_readWithAge() public {
        vm.expectRevert();
        scribe.readWithAge();
    }

    function test_tryReadWithAge() public {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = scribe.tryReadWithAge();
        assertFalse(ok);
        assertEq(val, 0);
        assertEq(age, 0);
    }

    // - MakerDAO Compatibility

    function test_peek() public {
        uint val;
        bool ok;
        (val, ok) = scribe.peek();
        assertEq(val, 0);
        assertFalse(ok);
    }

    function test_peep() public {
        uint val;
        bool ok;
        (val, ok) = scribe.peep();
        assertEq(val, 0);
        assertFalse(ok);
    }

    // - Chainlink Compatibility

    function test_lastRoundData() public {
        (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = scribe.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    function test_latestAnswer() public {
        int answer = scribe.latestAnswer();
        assertEq(answer, 0);
    }
}
