// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "../libs/LibFeed.sol";

/**
 * @notice Scribe Tester Script
 *
 * @dev !!! IMPORTANT !!!
 *
 *      This script may only be used for dev deployments!
 */
contract ScribeTesterScript is Script {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    /// @dev Lifts set of private keys `privKeys` on `self`.
    ///
    /// @dev Call via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///           --private-key $PRIVATE_KEY \
    ///           --broadcast \
    ///           --rpc-url $RPC_URL \
    ///           --sig $(cast calldata "lift(address,uint[])" $SCRIBE $TEST_FEED_PRIVATE_KEYS) \
    ///           -vvv \
    ///           script/dev/ScribeTester.s.sol:ScribeTesterScript
    ///      ```
    function lift(address self, uint[] memory privKeys) public {
        require(privKeys.length != 0, "No private keys given");

        // Setup feeds.
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](privKeys.length);
        for (uint i; i < feeds.length; i++) {
            feeds[i] = LibFeed.newFeed({privKey: privKeys[i]});

            vm.label(
                feeds[i].pubKey.toAddress(),
                string.concat("Feed #", vm.toString(i + 1))
            );
        }

        // Let feeds sign the feed registration message.
        IScribe.ECDSAData[] memory ecdsaDatas;
        ecdsaDatas = new IScribe.ECDSAData[](feeds.length);
        bytes32 message = IScribe(self).feedRegistrationMessage();
        for (uint i; i < feeds.length; i++) {
            ecdsaDatas[i] = feeds[i].signECDSA(message);
        }

        // Create list of public keys.
        LibSecp256k1.Point[] memory pubKeys;
        pubKeys = new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < pubKeys.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Lift feeds.
        vm.startBroadcast();
        IScribe(self).lift(pubKeys, ecdsaDatas);
        vm.stopBroadcast();

        console2.log("Lifted feeds");
    }

    /// @dev Pokes `self` with val `val` and current timestamp signed by set of
    ///      private keys `privKeys`.
    ///
    /// @dev Call via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///         --private-key $PRIVATE_KEY \
    ///         --broadcast \
    ///         --rpc-url $RPC_URL \
    ///         --sig $(cast calldata "poke(address,uint[],uint128)" $SCRIBE $TEST_FEED_SIGNERS_PRIVATE_KEYS $TEST_POKE_VAL) \
    ///         -vvv \
    ///         script/dev/ScribeTester.s.sol:ScribeTesterScript
    ///      ```
    function poke(address self, uint[] memory privKeys, uint128 val) public {
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
            bool isFeed = IScribe(self).feeds(feeds[i].pubKey.toAddress());
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
        bytes32 message = IScribe(self).constructPokeMessage(pokeData);

        // Create Schnorr data proving poke message's integrity.
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(message);

        // Poke scribe.
        vm.startBroadcast();
        IScribe(self).poke(pokeData, schnorrData);
        vm.stopBroadcast();

        console2.log(
            string.concat(
                "Poked, val=",
                vm.toString(pokeData.val),
                ", age=",
                vm.toString(pokeData.age)
            )
        );
    }
}
