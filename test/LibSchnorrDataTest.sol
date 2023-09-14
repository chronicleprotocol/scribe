// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSchnorrData} from "src/libs/LibSchnorrData.sol";

abstract contract LibSchnorrDataTest is Test {
    using LibSchnorrData for IScribe.SchnorrData;

    function testFuzz_loadFeedId(uint lengthSeed, uint indexSeed) public {
        // Let length be ∊ [1, 256].
        uint length = _bound(lengthSeed, 1, 256);

        // Let index be ∊ [0, length).
        uint8 index = uint8(_bound(indexSeed, 0, length - 1));

        bytes memory feedIds;
        for (uint i; i < length; i++) {
            if (i == index) {
                feedIds = abi.encodePacked(feedIds, uint8(0xFF));
            } else {
                feedIds = abi.encodePacked(feedIds, uint8(1));
            }
        }

        IScribe.SchnorrData memory schnorrData;
        schnorrData.feedIds = feedIds;

        uint got = this.loadFeedId(schnorrData, index);
        assertEq(got, uint8(0xFF));
    }

    function testFuzz_loadFeedId_ReturnsZeroIfIndexOutOfBounds(
        uint lengthSeed,
        uint indexSeed
    ) public {
        // Let length be ∊ [0, 256].
        uint length = _bound(lengthSeed, 0, 256);

        // Let index be ∊ [length, 256).
        uint8 index = uint8(_bound(indexSeed, length, 256));

        // Make sure that index is actually out of bounds.
        vm.assume(length <= index);

        bytes memory feedIds;
        for (uint i; i < length; i++) {
            feedIds = abi.encodePacked(feedIds, uint8(1));
        }

        IScribe.SchnorrData memory schnorrData;
        schnorrData.feedIds = feedIds;

        uint got = this.loadFeedId(schnorrData, index);
        assertEq(got, uint8(0));
    }

    function testFuzz_numberFeeds(uint lengthSeed) public {
        // Let length be ∊ [0, 256].
        uint length = bound(lengthSeed, 0, 256);

        bytes memory feedIds;
        for (uint i; i < length; i++) {
            feedIds = abi.encodePacked(feedIds, uint8(1));
        }

        IScribe.SchnorrData memory schnorrData;
        schnorrData.feedIds = feedIds;

        uint got = this.numberFeeds(schnorrData);
        assertEq(got, length);
    }

    // -- Optimizations --

    function testFuzzOptimization_loadFeedId_WordIndexComputation(uint index)
        public
    {
        // Previous implementation:
        uint want;
        assembly ("memory-safe") {
            want := mul(div(index, 32), 32)
        }

        // New implementation:
        uint mask = type(uint).max << 5;
        uint got = index & mask;

        assertEq(want, got);
    }

    function testFuzzOptimization_loadFeedId_ByteIndexComputation(uint index)
        public
    {
        // Previous implementation:
        uint want;
        unchecked {
            want = 31 - (index % 32);
        }

        // New implementation:
        uint mask = type(uint).max >> (256 - 5);
        uint got = (~index) & mask;

        assertEq(want, got);
    }

    // -- Executors --
    //
    // Used to move memory structs into calldata.

    function loadFeedId(IScribe.SchnorrData calldata schnorrData, uint8 index)
        public
        pure
        returns (uint)
    {
        return schnorrData.loadFeedId(index);
    }

    function numberFeeds(IScribe.SchnorrData calldata schnorrData)
        public
        pure
        returns (uint)
    {
        return schnorrData.numberFeeds();
    }
}
