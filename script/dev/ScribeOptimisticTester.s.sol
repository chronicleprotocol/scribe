// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeTesterScript} from "./ScribeTester.s.sol";

import {LibFeed} from "../libs/LibFeed.sol";

/**
 * @notice ScribeOptimistic Tester Script
 *
 * @dev !!! IMPORTANT !!!
 *
 *      This script may only be used for dev deployments!
 */
contract ScribeOptimisticTesterScript is ScribeTesterScript {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    /// @dev opPokes `self` with val `val` and current timestamp signed by set of
    ///      private keys `privKeys`. Note that a random private key is selected
    ///      to opPoke.
    ///
    /// @dev Call via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///           --private-key $PRIVATE_KEY \
    ///           --broadcast \
    ///           --rpc-url $RPC_URL \
    ///           --sig $(cast calldata "opPoke(address,uint[],uint128)" $SCRIBE $TEST_FEED_SIGNERS_PRIVATE_KEYS $TEST_POKE_VAL) \
    ///           -vvv \
    ///           script/dev/ScribeOptimisticTester.s.sol:ScribeOptimisticTesterScript
    ///      ```
    function opPoke(address self, uint[] memory privKeys, uint128 val) public {
        require(privKeys.length != 0, "No private keys given");

        // Setup feeds.
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](privKeys.length);
        for (uint i; i < feeds.length; i++) {
            feeds[i] = LibFeed.newFeed({privKey: privKeys[i]});

            vm.label(
                feeds[i].pubKey.toAddress(),
                string.concat("Feed #", vm.toString(i + 1))
            );

            // Verify feed is lifted.
            bool isFeed;
            (isFeed, /*feedId*/ ) =
                IScribe(self).feeds(feeds[i].pubKey.toAddress());
            require(
                isFeed,
                string.concat(
                    "Private key not feed, privKey=", vm.toString(privKeys[i])
                )
            );
        }

        // Create poke data.
        IScribe.PokeData memory pokeData;
        pokeData.val = val;
        pokeData.age = uint32(block.timestamp);

        // Construct poke message.
        bytes32 pokeMessage = IScribe(self).constructPokeMessage(pokeData);

        // Create Schnorr data proving poke message's integrity.
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(pokeMessage);

        // Use "random" feed to opPoke.
        LibFeed.Feed memory signer = feeds[val % feeds.length];

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = signer.signECDSA(
            IScribeOptimistic(self).constructOpPokeMessage(
                pokeData, schnorrData
            )
        );

        vm.startBroadcast();
        IScribeOptimistic(self).opPoke(pokeData, schnorrData, ecdsaData);
        vm.stopBroadcast();

        console2.log(
            string.concat(
                "opPoked, val=",
                vm.toString(pokeData.val),
                ", age=",
                vm.toString(pokeData.age)
            )
        );
    }

    /// @dev opPokes `self` with invalid signature for val `val` and current timestamp.
    ///      Note that a random private key is selected to opPoke.
    ///
    /// @dev Call via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///         --private-key $PRIVATE_KEY \
    ///         --broadcast \
    ///         --rpc-url $RPC_URL \
    ///         --sig $(cast calldata "opPoke_invalid(address,uint[],uint128)" $SCRIBE $TEST_FEED_SIGNERS_PRIVATE_KEYS $TEST_POKE_VAL) \
    ///         -vvv \
    ///         script/dev/ScribeOptimisticTester.s.sol:ScribeOptimisticTesterScript
    ///      ```
    function opPoke_invalid(address self, uint[] memory privKeys, uint128 val)
        public
    {
        require(privKeys.length != 0, "No private keys given");

        // Setup feeds.
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](privKeys.length);
        for (uint i; i < feeds.length; i++) {
            feeds[i] = LibFeed.newFeed({privKey: privKeys[i]});

            vm.label(
                feeds[i].pubKey.toAddress(),
                string.concat("Feed #", vm.toString(i + 1))
            );

            // Verify feed is lifted.
            bool isFeed;
            (isFeed, /*feedId*/ ) =
                IScribe(self).feeds(feeds[i].pubKey.toAddress());
            require(
                isFeed,
                string.concat(
                    "Private key not feed, privKey=", vm.toString(privKeys[i])
                )
            );
        }

        // Create poke data.
        IScribe.PokeData memory pokeData;
        pokeData.val = val;
        pokeData.age = uint32(block.timestamp);

        // Construct poke message.
        bytes32 pokeMessage = IScribe(self).constructPokeMessage(pokeData);

        // Create Schnorr data proving poke message's integrity.
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(pokeMessage);

        // Mutate Schnorr data to make signature invalid.
        schnorrData.commitment = address(uint160(schnorrData.commitment) + 1);

        // Use "random" feed to opPoke.
        LibFeed.Feed memory signer = feeds[val % feeds.length];

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = signer.signECDSA(
            IScribeOptimistic(self).constructOpPokeMessage(
                pokeData, schnorrData
            )
        );

        vm.startBroadcast();
        IScribeOptimistic(self).opPoke(pokeData, schnorrData, ecdsaData);
        vm.stopBroadcast();

        console2.log(
            string.concat(
                "opPoked, val=",
                vm.toString(pokeData.val),
                ", age=",
                vm.toString(pokeData.age)
            )
        );
    }

    /// @dev opChallenges `self`'s poke data `pokeData` and Schnorr signature
    ///      `schnorrData`.
    ///
    /// @dev Call via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///         --private-key $PRIVATE_KEY \
    ///         --broadcast \
    ///         --rpc-url $RPC_URL \
    ///         --sig $(cast calldata "opChallenge(address,uint128,uint32,bytes32,address,bytes)" $SCRIBE $TEST_POKE_VAL $TEST_POKE_AGE $TEST_SCHNORR_SIGNATURE $TEST_SCHNORR_COMMITMENT $TEST_SCHNORR_FEED_IDS) \
    ///         -vvv \
    ///         script/dev/ScribeOptimisticTester.s.sol:ScribeOptimisticTesterScript
    ///      ```
    function opChallenge(
        address self,
        uint128 val,
        uint32 age,
        bytes32 schnorrSignature,
        address schnorrCommitment,
        bytes memory schnorrFeedIds
    ) public {
        // Construct pokeData and schnorrData.
        IScribe.PokeData memory pokeData;
        pokeData.val = val;
        pokeData.age = age;

        IScribe.SchnorrData memory schnorrData;
        schnorrData.signature = schnorrSignature;
        schnorrData.commitment = schnorrCommitment;
        schnorrData.feedIds = schnorrFeedIds;

        // Create poke message from pokeData.
        bytes32 pokeMessage = IScribe(self).constructPokeMessage(pokeData);

        // Check whether schnorrData is not acceptable.
        bool ok = IScribe(self).isAcceptableSchnorrSignatureNow(
            pokeMessage, schnorrData
        );
        if (ok) {
            console2.log(
                "Schnorr signature is acceptable: expecting opChallenge to be unsuccessful"
            );
        } else {
            console2.log(
                "Schnorr signature is unacceptable: expecting opChallenge to be successful"
            );
        }

        // Challenge opPoke.
        vm.startBroadcast();
        ok = IScribeOptimistic(self).opChallenge(schnorrData);
        vm.stopBroadcast();

        console2.log(string.concat("OpChallenged, ok=", vm.toString(ok)));
    }
}
