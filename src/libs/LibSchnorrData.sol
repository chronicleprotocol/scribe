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

    /// @dev Mask to compute word index of an array index.
    ///
    /// @dev Equals `type(uint).max << 5`.
    uint private constant WORD_MASK =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0;

    /// @dev Mask to compute byte index of an array index.
    ///
    /// @dev Equals `type(uint).max >> (256 - 5)`.
    uint private constant BYTE_MASK = 31;

    /// @dev Returns the feedId from schnorrData.feedIds with index `index`.
    ///
    /// @dev Note that schnorrData.feedIds is big-endian encoded and
    ///      counting starts at the highest order byte, i.e. the feedId with
    ///      index 0 is the highest order byte of schnorrData.feedIds.
    ///
    /// @custom:example Encoding feedIds via Solidity:
    ///
    ///      ```solidity
    ///      bytes memory feedIds;
    ///      uint8[] memory ids = someFuncReturningUint8Array();
    ///      for (uint i; i < ids.length; i++) {
    ///          feedIds = abi.encodePacked(feedIds, ids[i]);
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
    function loadFeedId(IScribe.SchnorrData calldata schnorrData, uint8 index)
        internal
        pure
        returns (uint8)
    {
        uint wordIndex = index & WORD_MASK;
        uint byteIndex = (~index) & BYTE_MASK;

        uint word;
        assembly ("memory-safe") {
            // Calldata index for schnorrData.feedIds[0] is schnorrData's offset
            // plus 4 words, i.e. 0x80.
            let feedIdsOffset := add(schnorrData, 0x80)

            // Note that reading non-existing calldata returns zero.
            word := calldataload(add(feedIdsOffset, wordIndex))
        }

        return word.getByteAtIndex(byteIndex);
    }

    /// @dev Returns the number of feed ids' encoded in schnorrData.feedIds.
    function numberFeeds(IScribe.SchnorrData calldata schnorrData)
        internal
        pure
        returns (uint)
    {
        uint result;
        assembly ("memory-safe") {
            // Calldata index for schnorrData.feedIds.length is
            // schnorrData's offset plus 3 words, i.e. 0x60.
            result := calldataload(add(schnorrData, 0x60))
        }
        return result;
    }
}
