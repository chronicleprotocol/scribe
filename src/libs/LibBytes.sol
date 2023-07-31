// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title LibBytes
 *
 * @notice Library for common byte operations
 */
library LibBytes {
    /// @dev Returns the `index`'s byte from `word`.
    ///
    ///      It is the caller's responsibility to ensure `index < 32`!
    ///
    /// @custom:invariant Uses constant amount of gas.
    function getByteAtIndex(uint word, uint index)
        internal
        pure
        returns (uint)
    {
        uint result;

        // Shift byte at index to be least significant byte and afterwards
        // mask off all remaining bytes.
        // Note that << 3 equals a multiplication by 8.
        result = (word >> (index << 3)) & 0xFF;

        // Note that the resulting byte is returned as word.
        return result;
    }
}
