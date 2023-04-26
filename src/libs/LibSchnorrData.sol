pragma solidity ^0.8.16;

import {IScribe} from "../IScribe.sol";

import {LibBytes} from "./LibBytes.sol";

/**
 * @title
 *
 * @notice
 */
library LibSchnorrData {
    using LibBytes for uint;

    /// @dev Size of a word is 32 bytes, i.e. 245 bits.
    uint private constant WORD_SIZE = 32;

    // @todo Big-endian encoded.
    /// @dev Calldata layout for `schnorrData`:
    ///
    ///      [schnorrData]        signature             -> schnorrData.signature
    ///      [schnorrData + 0x20] commitment            -> schnorrData.commitment
    ///      [schnorrData + 0x40] offset(signersBlob)
    ///      [schnorrData + 0x60] len(signersBlob)      -> schnorrData.signersBlob.length
    ///      [schnorrData + 0x80] signersBlob[0]        -> schnorrData.signersBlob[0]
    ///      ...
    ///
    ///      Note that the `schnorrData` variable holds the offset to the
    ///      `schnorrData` struct:
    ///
    ///      ```solidity
    ///      bytes32 signature;
    ///      assembly {
    ///         signature := calldataload(schnorrData)
    ///      }
    ///      assert(signature == schnorrData.signature)
    ///      ```
    ///
    ///      Note that `offset(signersBlob)` is the offset to `signersBlob[0]`
    ///      from the index `offset(signersBlob)`.
    function getSignerIndex(
        IScribe.SchnorrData calldata schnorrData,
        uint index
    ) internal pure returns (uint) {
        uint wordIndex = (index / WORD_SIZE) * WORD_SIZE;
        uint byteIndex = 31 - (index % WORD_SIZE);

        uint word;
        assembly ("memory-safe") {
            // Calldata index for schnorrData.signersBlob[0] is schnorrData's
            // offset plus 4 words, i.e. 0x80.
            let start := add(schnorrData, 0x80)
            // Note that overflow is not a problem. @todo lol... right, but why?
            // Note that reading non existing calldata returns zero.
            word := calldataload(add(start, wordIndex))
        }

        return word.getByteAtIndex(byteIndex);
    }

    function getSignerIndexLength(IScribe.SchnorrData calldata schnorrData)
        internal
        pure
        returns (uint)
    {
        return schnorrData.signersBlob.length;
    }
}
