// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IToll} from "chronicle-std/toll/IToll.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {Chronicle_BASE_QUOTE_COUNTER as ScribeOptimistic} from
    "src/ScribeOptimistic.sol";
// @todo          ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeScript} from "./Scribe.s.sol";

/**
 * @title ScribeOptimistic Management Script
 */
contract ScribeOptimisticScript is ScribeScript {
    /// @dev Deploys a new ScribeOptimistic instance via Greenhouse instance
    ///      `greenhouse` and salt `salt` with `initialAuthed` being the address
    ///      initially auth'ed. Note that zero address is kissed directly after
    ///      deployment.
    function deploy(
        address greenhouse,
        bytes32 salt,
        address initialAuthed,
        bytes32 wat
    ) public override(ScribeScript) {
        // Create creation code with constructor arguments.
        bytes memory creationCode = abi.encodePacked(
            type(ScribeOptimistic).creationCode, abi.encode(initialAuthed, wat)
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        // Plant creation code via greenhouse and kiss zero address.
        vm.startBroadcast();
        require(msg.sender == initialAuthed, "Deployer must be initial auth'ed");
        IGreenhouse(greenhouse).plant(salt, creationCode);
        IToll(deployed).kiss(address(0));
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
    }

    // -- IScribeOptimistic Functions --

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
