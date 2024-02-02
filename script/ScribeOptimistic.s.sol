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

    /// @dev opPokes `self` with arguments given via calldata payload `payload`.
    ///
    /// @dev Note that this function can be used to simulate - or execute -
    ///      opPokes with an already fully constructed payload.
    ///
    /// @dev Call via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///           --private-key $PRIVATE_KEY \
    ///           --broadcast \
    ///           --rpc-url $RPC_URL \
    ///           --sig $(cast calldata "opPokeRaw(address,bytes)" $SCRIBE $PAYLOAD) \
    ///           -vvvvv \
    ///           script/dev/ScribeOptimistic.s.sol:ScribeOptimisticScript
    ///      ```
    ///
    ///      Note to remove `--broadcast` to just simulate the opPoke.
    function opPokeRaw(address self, bytes calldata payload) public {
        // Note to remove first 4 bytes, ie the function selector, from the
        // payload to receive the arguments.
        bytes calldata args = payload[4:];

        // Decode arguments into opPoke argument types.
        IScribe.PokeData memory pokeData;
        IScribe.SchnorrData memory schnorrData;
        IScribe.ECDSAData memory ecdsaData;
        (pokeData, schnorrData, ecdsaData) = abi.decode(
            args, (IScribe.PokeData, IScribe.SchnorrData, IScribe.ECDSAData)
        );

        // Print arguments.
        console2.log("PokeData");
        console2.log("- val :", pokeData.val);
        console2.log("- age :", pokeData.age);
        console2.log("SchnorrData");
        console2.log("- signature  :", uint(schnorrData.signature));
        console2.log("- commitment :", schnorrData.commitment);
        console2.log("- feedIds    :", vm.toString(schnorrData.feedIds));
        console2.log("ECDSAData");
        console2.log("- v :", ecdsaData.v);
        console2.log("- r :", uint(ecdsaData.r));
        console2.log("- s :", uint(ecdsaData.s));

        // Execute opPoke.
        vm.startBroadcast();
        IScribeOptimistic(self).opPoke(pokeData, schnorrData, ecdsaData);
        vm.stopBroadcast();
    }
}
