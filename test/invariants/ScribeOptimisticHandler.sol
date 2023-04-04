pragma solidity ^0.8.16;

import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeHandler} from "./ScribeHandler.sol";

import {LibHelpers} from "../utils/LibHelpers.sol";

contract ScribeOptimisticHandler is ScribeHandler {
    using LibSecp256k1 for LibSecp256k1.Point;

    uint public constant MAX_OP_CHALLENGE_PERIOD = 1 hours;

    IScribeOptimistic public opScribe;

    /*//////////////////////////////////////////////////////////////
                            TARGET FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function opPoke() external {}

    function opChallenge() external {}

    function setOpChallengePeriod(uint16 opChallengePeriodSeed) external {
        uint16 newOpChallengePeriod =
            uint16(bound(opChallengePeriodSeed, 1, MAX_OP_CHALLENGE_PERIOD));

        // Reverts if newOpChallengePeriod is 0.
        opScribe.setOpChallengePeriod(newOpChallengePeriod);
    }
}
