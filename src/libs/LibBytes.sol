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
    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Does not run into an infinite loop.
    function getByteAtIndex(uint word, uint index)
        internal
        pure
        returns (uint)
    {
        uint result;

        // Unchecked because the only protected operation is the subtraction of
        // index from 31, where index is guaranteed by the caller to be less
        // than 32.
        unchecked {
            // Shift byte at index to be least significant byte and afterwards
            // mask off all remaining bytes.
            // Note that << 3 equals a multiplication by 8.
            result = (word >> ((31 - index) << 3)) & 0xFF;
        }

        // Note that the resulting byte is returned as word.
        return result;
    }
}
