pragma solidity ^0.8.16;

import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {ScribeOptimisticInspectable} from
    "../inspectable/ScribeOptimisticInspectable.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeInvariantTest} from "./IScribeInvariantTest.sol";
import {ScribeOptimisticHandler} from "./ScribeOptimisticHandler.sol";

abstract contract IScribeOptimisticInvariantTest is IScribeInvariantTest {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeOptimistic private opScribe;
    ScribeOptimisticHandler private opHandler;

    // @todo invariant: If challengeable, Searcher script always succeeds.

    function setUp(address scribe_, address handler_)
        internal
        override(IScribeInvariantTest)
    {
        super.setUp(scribe_, handler_);

        opScribe = ScribeOptimisticInspectable(payable(scribe_));
        opHandler = ScribeOptimisticHandler(handler_);
    }

    function _targetSelectors()
        internal
        override(IScribeInvariantTest)
        returns (bytes4[] memory)
    {
        bytes4[] memory initial = super._targetSelectors();

        bytes4[] memory selectors = new bytes4[](3 + initial.length);
        for (uint i; i < initial.length; i++) {
            selectors[i] = initial[i];
        }
        selectors[selectors.length - 3] =
            ScribeOptimisticHandler.setOpChallengePeriod.selector;
        selectors[selectors.length - 2] =
            ScribeOptimisticHandler.opPoke.selector;
        selectors[selectors.length - 1] =
            ScribeOptimisticHandler.opChallenge.selector;

        return selectors;
    }

    // -- opPoke --

    // -- opChallenge --

    // -- opChallenge Period --

    function invariant_opChallengePeriod_IsNeverZero() public {
        assertTrue(opScribe.opChallengePeriod() != 0);
    }
}
