pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "src/IScribeOptimisticAuth.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeInvariantTest} from "./IScribeInvariantTest.sol";
import {ScribeOptimisticHandler} from "./ScribeOptimisticHandler.sol";

abstract contract IScribeOptimisticInvariantTest is IScribeInvariantTest {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeOptimistic opScribe;
    ScribeOptimisticHandler opHandler;

    function setUp(address scribe_, address handler_)
        internal
        override(IScribeInvariantTest)
    {
        super.setUp(scribe_, handler_);

        opScribe = IScribeOptimistic(scribe_);
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

    /*//////////////////////////////////////////////////////////////
                      INVARIANT OpChallengePeriod
    //////////////////////////////////////////////////////////////*/

    function invariant_opChallengePeriod_IsNeverZero() public {
        assertTrue(
            IScribeOptimisticAuth(address(opScribe)).opChallengePeriod() != 0
        );
    }
}
