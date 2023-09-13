// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IScribe} from "../IScribe.sol";

import {LibBytes} from "./LibBytes.sol";

/**
 * @title LibSchnorrData
 *
 * @notice Library for working with IScribe.SchnorrData
 */
library LibSchnorrData {
    using LibBytes for uint;

    /// @dev Size of a word is 32 bytes, i.e. 256 bits.
    uint private constant WORD_SIZE = 32;

    uint private constant BYTE_BOUNDARY_MASK = type(uint).max >> (256 - 5);

    // @todo Docs
    /// @dev Returns the feedId from schnorrData.feedIds with index `index`.
    ///
    /// @dev Note that schnorrData.feedIds is big-endian encoded and
    ///      counting starts at the highest order byte, i.e. the feedId 0 is
    ///      the highest order byte of schnorrData.feedIds.
    ///
    /// @custom:example FeedIds encoding via Solidity:
    ///
    ///      ```solidity
    ///      bytes memory feedIds;
    ///      uint8[] memory indexes = someFuncReturningUint8Array();
    ///      for (uint i; i < indexes.length; i++) {
    ///          feedIds = abi.encodePacked(feedIds, indexes[i]);
    ///      }
    ///      ```
    ///
    /// @dev Calldata layout for `schnorrData`:
    ///
    ///      [schnorrData]        signature        -> schnorrData.signature
    ///      [schnorrData + 0x20] commitment       -> schnorrData.commitment
    ///      [schnorrData + 0x40] offset(feedIds)
    ///      [schnorrData + 0x60] len(feedIds)     -> schnorrData.feedIds.length
    ///      [schnorrData + 0x80] feedIds[0]       -> schnorrData.feedIds[0]
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
    ///      Note that `offset(feedIds)` is the offset to `feedIds[0]` from the
    ///      index `offset(feedIds)`.
    ///
    /// @custom:invariant Reverts iff out of gas.
    function loadFeedId(
        IScribe.SchnorrData calldata schnorrData,
        uint index
    ) internal pure returns (uint8) {
        uint word;
        assembly ("memory-safe") {
            let wordIndex := mul(div(index, WORD_SIZE), WORD_SIZE)

            // Calldata index for schnorrData.signersBlob[0] is schnorrData's
            // offset plus 4 words, i.e. 0x80.
            let start := add(schnorrData, 0x80)

            // Note that reading non-existing calldata returns zero.
            // Note that overflow is no concern because index's upper limit is
            // bounded by bar, which is of type uint8.
            word := calldataload(add(start, wordIndex))
        }

        uint byteIndex = (~index) & BYTE_BOUNDARY_MASK;

        return word.getByteAtIndex(byteIndex);
    }

    /// @dev Returns the number of feed ids' encoded in schnorrData.feedIds.
    function numberFeeds(IScribe.SchnorrData calldata schnorrData)
        internal
        pure
        returns (uint8)
    {
        uint8 result;
        assembly ("memory-safe") {
            // Calldata index for schnorrData.feedIds.length is
            // schnorrData's offset plus 3 words, i.e. 0x60.
            result := calldataload(add(schnorrData, 0x60))
        }
        return result;
    }
}
