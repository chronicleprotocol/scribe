pragma solidity ^0.8.16;

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {ScribeScript} from "./Scribe.s.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title ScribeOptimistic Management Script
 */
abstract contract ScribeOptimisticScript is ScribeScript {
    function opPoke(
        address self,
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrData memory schnorrData,
        IScribe.ECDSAData memory ecdsaData
    ) public {
        vm.broadcast();
        IScribeOptimistic(self).opPoke(pokeData, schnorrData, ecdsaData);
    }

    function opChallenge(address self, IScribe.SchnorrData memory schnorrData)
        public
    {
        vm.broadcast();
        IScribeOptimistic(self).opChallenge(schnorrData);
    }

    function setOpChallengePeriod(address self, uint16 opChallengePeriod)
        public
    {
        vm.broadcast();
        IScribeOptimistic(self).setOpChallengePeriod(opChallengePeriod);
    }

    function setMaxChallengeReward(address self, uint maxChallengeReward)
        public
    {
        vm.broadcast();
        IScribeOptimistic(self).setMaxChallengeReward(maxChallengeReward);
    }
}
