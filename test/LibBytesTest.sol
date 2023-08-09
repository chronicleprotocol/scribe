// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {LibBytes} from "src/libs/LibBytes.sol";

abstract contract LibBytesTest is Test {
    using LibBytes for uint;

    function testFuzz_getByteAtIndex(uint8 wantByte, uint indexSeed) public {
        // Let index ∊ [0, 32).
        uint index = bound(indexSeed, 0, 31);

        // Create word with wantByte at byte index.
        uint word = uint(wantByte) << (index * 8);

        uint8 gotByte = uint8(word.getByteAtIndex(index));

        assertEq(wantByte, gotByte);
    }

    function test_getByteAtIndex() public {
        uint word;
        uint index;
        uint want;
        uint got;

        // Most significant byte.
        word =
            0xFF11111111111111111111111111111111111111111111111111111111111111;
        index = 31;
        want = 0xFF;
        got = word.getByteAtIndex(index);
        assertEq(want, got);

        // Least significant byte.
        word =
            0x11111111111111111111111111111111111111111111111111111111111111FF;
        index = 0;
        want = 0xFF;
        got = word.getByteAtIndex(index);
        assertEq(want, got);

        word =
            0x111111111111111111111111111111111111111111111111111111111111AA11;
        index = 1;
        want = 0xAA;
        got = word.getByteAtIndex(index);
        assertEq(want, got);

        word =
            0x1111001111111111111111111111111111111111111111111111111111111111;
        index = 29;
        want = 0x00;
        got = word.getByteAtIndex(index);
        assertEq(want, got);
    }
}
