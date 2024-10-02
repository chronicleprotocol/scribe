// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {Chronicle_BASE_QUOTE_COUNTER as ScribeOptimistic} from
    "src/ScribeOptimistic.sol";
// @todo          ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeScript} from "./Scribe.s.sol";

import {LibRandom} from "./libs/LibRandom.sol";
import {LibFeed} from "./libs/LibFeed.sol";

import {Rescuer} from "./rescue/Rescuer.sol";

/**
 * @title ScribeOptimistic Management Script
 */
contract ScribeOptimisticScript is ScribeScript {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;

    /// @dev Deploys a new ScribeOptimistic instance with `initialAuthed` being
    ///      the address initially auth'ed. Note that zero address is kissed
    ///      directly after deployment.
    function deploy(address initialAuthed, bytes32 wat)
        public
        override(ScribeScript)
    {
        vm.startBroadcast();
        require(msg.sender == initialAuthed, "Deployer must be initial auth'ed");
        address deployed = address(new ScribeOptimistic(initialAuthed, wat));
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
    ///      ```bash
    ///      $ forge script \
    ///           --keystore $KEYSTORE \
    ///           --password $KEYSTORE_PASSWORD \
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

    /// @dev Rescues ETH held in deactivated `self`.
    ///
    /// @dev Call via:
    ///      ```bash
    ///      $ forge script \
    ///           --keystore $KEYSTORE \
    ///           --password $KEYSTORE_PASSWORD \
    ///           --broadcast \
    ///           --rpc-url $RPC_URL \
    ///           --sig $(cast calldata "rescueETH(address,address)" $SCRIBE $RESCUER) \
    ///           -vvvvv \
    ///           script/dev/ScribeOptimistic.s.sol:ScribeOptimisticScript
    ///      ```
    function rescueETH(address self, address rescuer) public {
        // Require self to be deactivated.
        {
            vm.prank(address(0));
            (bool ok, /*val*/ ) = IScribe(self).tryRead();
            require(!ok, "Instance not deactivated: read() does not fail");

            require(
                IScribe(self).feeds().length == 0,
                "Instance not deactivated: Feeds still lifted"
            );
            require(
                IScribe(self).bar() == 255,
                "Instance not deactivated: Bar not type(uint8).max"
            );
        }

        // Ensure challenge reward is total balance.
        uint challengeReward = IScribeOptimistic(self).challengeReward();
        uint total = self.balance;
        if (challengeReward < total) {
            IScribeOptimistic(self).setMaxChallengeReward(type(uint).max);
        }

        // Create new random private key.
        uint privKeySeed = LibRandom.readUint();
        uint privKey = _bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Create feed instance from private key.
        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        // Let feed sign feed registration message.
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            feed.signECDSA(IScribe(self).feedRegistrationMessage());

        // Construct pokeData and invalid Schnorr signature.
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.PokeData memory pokeData = IScribe.PokeData(0, pokeDataAge);
        IScribe.SchnorrData memory schnorrData =
            IScribe.SchnorrData(bytes32(0), address(0), hex"");

        // Construct opPokeMessage.
        bytes32 opPokeMessage = IScribeOptimistic(self).constructOpPokeMessage(
            pokeData, schnorrData
        );

        // Let feed sign opPokeMessage.
        IScribe.ECDSAData memory opPokeSig = feed.signECDSA(opPokeMessage);

        // Rescue ETH via rescuer contract.
        Rescuer(payable(rescuer)).suck(
            self, feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
    }
}
