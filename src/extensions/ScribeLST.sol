// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IScribeLST} from "./IScribeLST.sol";
import {IRateSource} from "./external_/interfaces/IRateSource.sol";

import {Scribe} from "../Scribe.sol";

/**
 * @title ScribeLST
 *
 * @notice Schnorr based Oracle with onchain fault resolution for Liquid
 *         Staking Token APRs.
 */
contract ScribeLST is IScribeLST, Scribe {
    constructor(address initialAuthed_, bytes32 wat_)
        Scribe(initialAuthed_, wat_)
    {}

    /// @inheritdoc IRateSource
    /// @dev Only callable by toll'ed address.
    function getAPR() external view toll returns (uint) {
        // Note that function does not revert if val is zero.
        return _pokeData.val;
    }
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 *
 *      For more info, see docs/Deployment.md.
 */
contract Chronicle_BASE_QUOTE_COUNTER is ScribeLST {
    // @todo       ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.
    constructor(address initialAuthed, bytes32 wat_)
        ScribeLST(initialAuthed, wat_)
    {}
}
