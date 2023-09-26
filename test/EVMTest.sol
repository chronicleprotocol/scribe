// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

abstract contract EVMTest is Test {
    /// @dev Tests that an assembly calldataload from an out-of-bounds calldata
    ///      index returns 0.
    ///      Note that ScribeOptimistic::opChallenge() requires such an
    ///      expression to _not revert_.
    function testFuzz_calldataload_ReadingNonExistingCalldataReturnsZero(
        uint index
    ) public {
        uint minIndex;
        assembly ("memory-safe") {
            minIndex := calldatasize()
        }
        vm.assume(minIndex <= index);

        uint got;
        assembly ("memory-safe") {
            got := calldataload(index)
        }
        assertEq(got, 0);
    }

    /// @dev Tests that:
    ///         s ∊ [Q, type(uint).max] → ecrecover(_, _, _, s) = address(0)
    function testFuzz_ecrecover_ReturnsZeroAddress_If_S_IsGreaterThanOrEqualToQ(
        uint privKeySeed,
        uint sSeed
    ) public {
        // Let privKey ∊ [1, Q).
        uint privKey = _bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Let s ∊ [Q, type(uint).max].
        bytes32 s = bytes32(_bound(sSeed, LibSecp256k1.Q(), type(uint).max));

        // Create ECDSA signature.
        (, bytes32 r,) = vm.sign(privKey, keccak256("scribe"));

        assertEq(ecrecover(keccak256("scribe"), 27, r, s), address(0));
        assertEq(ecrecover(keccak256("scribe"), 28, r, s), address(0));
    }

    /// @dev Tests that:
    ///         ecrecover(_, _, 0, _) = address(0)
    function testFuzz_ecrecover_ReturnsZeroAddress_If_R_IsZero(uint privKeySeed)
        public
    {
        // Let privKey ∊ [1, Q).
        uint privKey = _bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Create ECDSA signature.
        (,, bytes32 s) = vm.sign(privKey, keccak256("scribe"));

        assertEq(ecrecover(keccak256("scribe"), 27, 0, s), address(0));
        assertEq(ecrecover(keccak256("scribe"), 28, 0, s), address(0));
    }
}
