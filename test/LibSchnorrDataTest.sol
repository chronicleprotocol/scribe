pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSchnorrData} from "src/libs/LibSchnorrData.sol";

abstract contract LibSchnorrDataTest is Test {
    using LibSchnorrData for IScribe.SchnorrData;

    function testFuzz_getSignerIndex(uint lengthSeed, uint indexSeed) public {
        // Let length be ∊ [1, type(uint8).max].
        uint length = bound(lengthSeed, 1, type(uint8).max);

        // Let index be ∊ [0, length).
        uint index = bound(indexSeed, 0, length - 1);

        bytes memory signersBlob;
        for (uint i; i < length; i++) {
            if (i == index) {
                signersBlob = abi.encodePacked(signersBlob, uint8(0xFF));
            } else {
                signersBlob = abi.encodePacked(signersBlob, uint8(1));
            }
        }

        IScribe.SchnorrData memory schnorrData;
        schnorrData.signersBlob = signersBlob;

        uint got = this.getSignerIndex(schnorrData, index);
        assertEq(got, uint8(0xFF));
    }

    function testFuzz_getSingerIndex_ReturnsZeroIfIndexOutOfBounds(
        uint lengthSeed,
        uint indexSeed
    ) public {
        // Let length be ∊ [0, type(uint8).max].
        uint length = bound(lengthSeed, 0, type(uint8).max);

        // Let index be ∊ [length, type(uint8).max].
        // Note that index's upper limit is bounded is bounded by bar, which is
        // of type uint8.
        uint index = bound(indexSeed, length, type(uint8).max);

        bytes memory signersBlob;
        for (uint i; i < length; i++) {
            signersBlob = abi.encodePacked(signersBlob, uint8(1));
        }

        IScribe.SchnorrData memory schnorrData;
        schnorrData.signersBlob = signersBlob;

        uint got = this.getSignerIndex(schnorrData, index);
        assertEq(got, uint8(0));
    }

    function testFuzz_getSignerIndexLength(uint lengthSeed) public {
        // Let length be ∊ [0, type(uint8).max].
        uint length = bound(lengthSeed, 0, type(uint8).max);

        bytes memory signersBlob;
        for (uint i; i < length; i++) {
            signersBlob = abi.encodePacked(signersBlob, uint8(1));
        }

        IScribe.SchnorrData memory schnorrData;
        schnorrData.signersBlob = signersBlob;

        uint got = this.getSignerIndexLength(schnorrData);
        assertEq(got, length);
    }

    // -- Optimizations --

    /// @dev Tests correctness of a possible optimization.
    ///
    ///      Note that the optimization is currently not implemented.
    function testFuzzOptimization_getSignerIndex_WordIndexComputation(
        uint index
    ) public {
        // Current implementation:
        uint want;
        assembly ("memory-safe") {
            want := mul(div(index, 32), 32)
        }

        // Possible optimization:
        uint mask = type(uint).max << 5;
        uint got = index & mask;

        assertEq(want, got);
    }

    /// @dev Tests correctness of a possible optimization.
    ///
    ///      Note that the optimization is currently not implemented.
    function testFuzzOptimization_getSignerIndex_ByteIndexComputation(
        uint index
    ) public {
        // Current implementation:
        uint want;
        unchecked {
            want = 31 - (index % 32);
        }

        // Possible optimization:
        uint mask = type(uint).max >> (256 - 5);
        uint got = (~index) & mask;

        assertEq(want, got);
    }

    // -- Executors --
    //
    // Used to move memory structs into calldata.

    function getSignerIndex(
        IScribe.SchnorrData calldata schnorrData,
        uint index
    ) public pure returns (uint) {
        return schnorrData.getSignerIndex(index);
    }

    function getSignerIndexLength(IScribe.SchnorrData calldata schnorrData)
        public
        pure
        returns (uint)
    {
        return schnorrData.getSignerIndexLength();
    }
}
