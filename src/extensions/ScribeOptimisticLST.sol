// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IScribeOptimisticLST} from "./IScribeOptimisticLST.sol";
import {IRateSource} from "./external_/interfaces/IRateSource.sol";

import {ScribeOptimistic} from "../ScribeOptimistic.sol";

/**
 * @title ScribeOptimisticLST
 *
 * @notice Schnorr based optimistic Oracle with onchain fault resolution for
 *         Liquid Staking Token APRs.
 */
contract ScribeOptimisticLST is IScribeOptimisticLST, ScribeOptimistic {
    constructor(address initialAuthed_, bytes32 wat_)
        ScribeOptimistic(initialAuthed_, wat_)
    {}

    /// @inheritdoc IRateSource
    /// @dev Only callable by toll'ed address.
    function getAPR() external view toll returns (uint) {
        // Note that function does not revert if val is zero.
        return _currentPokeData().val;
    }
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 *
 *      For more info, see docs/Deployment.md.
 */
contract Chronicle_BASE_QUOTE_COUNTER is ScribeOptimisticLST {
    // @todo       ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.
    constructor(address initialAuthed, bytes32 wat_)
        ScribeOptimisticLST(initialAuthed, wat_)
    {}
}
