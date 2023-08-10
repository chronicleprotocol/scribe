// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeScript} from "./Scribe.s.sol";

contract Chronicle_BASE_QUOTE_COUNTER is ScribeOptimistic {
    // @todo Adjust name's BASE, QUOTE and COUNTER.
    constructor(address initialAuthed, bytes32 wat_)
        ScribeOptimistic(initialAuthed, wat_)
    {}
}

/**
 * @title ScribeOptimistic Management Script
 */
contract ScribeOptimisticScript is ScribeScript {
    /// @dev Deploys a new ScribeOptimistic instance via Greenhouse instance
    ///      `greenhouse` and salt `salt` with `initialAuthed` being the address
    ///      initially auth'ed.
    function deploy(
        address greenhouse,
        bytes32 salt,
        address initialAuthed,
        bytes32 wat
    ) public override(ScribeScript) {
        // Create creation code with constructor arguments.
        bytes memory creationCode = abi.encodePacked(
            type(Chronicle_BASE_QUOTE_COUNTER).creationCode,
            // @todo Adjust name's BASE, QUOTE and COUNTER.
            abi.encode(initialAuthed, wat)
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        // Plant creation code via greenhouse.
        vm.startBroadcast();
        IGreenhouse(greenhouse).plant(salt, creationCode);
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
    }

    /// @dev Sets the opChallengePeriod of `self` to `opChallengePeriod`.
    function setOpChallengePeriod(address self, uint16 opChallengePeriod)
        public
    {
        vm.startBroadcast();
        IScribeOptimistic(self).setOpChallengePeriod(opChallengePeriod);
        vm.stopBroadcast();

        console2.log("OpChallengePeriod set to", opChallengePeriod);
    }

    /// @dev Sets the maxChallengeReward of `self` to `maxChallengeReward`.
    function setMaxChallengeReward(address self, uint maxChallengeReward)
        public
    {
        vm.startBroadcast();
        IScribeOptimistic(self).setMaxChallengeReward(maxChallengeReward);
        vm.stopBroadcast();

        console2.log("MaxChallengeReward set to", maxChallengeReward);
    }
}
