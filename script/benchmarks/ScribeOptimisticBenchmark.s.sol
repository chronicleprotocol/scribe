// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

/**
 * @notice Scribe Optimistic Benchmark Script
 *
 * @dev Usage:
 *      1. Open new terminal and start anvil via:
 *          $ anvil -b 1
 *
 *      2. Deploy contract via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "deploy()"
 *
 *      3. Set bar via:
 *          $ BAR=10 # Note to update to appropriate value
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig $(cast calldata "setBar(uint8)" $BAR)
 *
 *      4. Lift feeds via:
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()"
 *
 *      5. Set opChallengePeriod via:
 *          $ OP_CHALLENGE_PERIOD=1 # Note to update to appropriate value
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig $(cast calldata "setOpChallengePeriod(uint16)" $OP_CHALLENGE_PERIOD)"
 *
 *      6. Poke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()"
 *
 *      7. opPoke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "opPoke()"
 *
 *      Note to (op)Poke more than once to get realistic gas costs.
 *      During the first execution the storage slots are empty.
 */
contract ScribeOptimisticBenchmark is Script {
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    ScribeOptimistic opScribe = ScribeOptimistic(
        payable(address(0x5FbDB2315678afecb367f032d93F642f64180aa3))
    );

    function deploy() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.broadcast(deployer);
        opScribe = new ScribeOptimistic(vm.addr(deployer), "ETH/USD");
    }

    function setBar(uint8 bar) public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.broadcast(deployer);
        opScribe.setBar(bar);
    }

    function setOpChallengePeriod(uint16 opChallengePeriod) public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Note to set opChallengePeriod to small value.
        vm.broadcast(deployer);
        opScribe.setOpChallengePeriod(opChallengePeriod);
    }

    function liftFeeds() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Create bar many feeds.
        LibFeed.Feed[] memory feeds = _createFeeds(opScribe.bar());

        // Create list of feeds' public keys and ECDSA signatures.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        IScribe.ECDSAData[] memory sigs = new IScribe.ECDSAData[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
            sigs[i] = feeds[i].signECDSA(opScribe.feedRegistrationMessage());
        }

        // Lift feeds.
        vm.broadcast(deployer);
        opScribe.lift(pubKeys, sigs);
    }

    function poke() public {
        uint relay = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

        // Create bar many feeds.
        LibFeed.Feed[] memory feeds = _createFeeds(opScribe.bar());

        // Create list of feeds' public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Create pokeData.
        // Note to use max value for val to have highest possible gas costs.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: type(uint128).max,
            age: uint32(block.timestamp)
        });

        // Create schnorrData.
        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        // Execute poke.
        vm.broadcast(relay);
        opScribe.poke(pokeData, schnorrData);
    }

    function opPoke() public {
        uint relay = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

        // Create bar many feeds.
        LibFeed.Feed[] memory feeds = _createFeeds(opScribe.bar());

        // Create pokeData.
        // Note to use max value for val to have highest possible gas costs.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: type(uint128).max,
            age: uint32(block.timestamp)
        });

        // Create schnorrData.
        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        // Create ecdsaData.
        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute opPoke.
        vm.broadcast(relay);
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function opPokeInvalidAndChallenge() public {
        uint relay = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));
        uint challenger = vm.deriveKey(ANVIL_MNEMONIC, uint32(2));

        // Create bar many feeds.
        LibFeed.Feed[] memory feeds = _createFeeds(opScribe.bar());

        // Create pokeData.
        // Note to use max value for val to have highest possible gas costs.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: type(uint128).max,
            age: uint32(block.timestamp)
        });

        // Create schnorrData.
        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        // Mutate pokeData to make Schnorr signature invalid.
        // Note to mutate before creating ECDSA signature.
        pokeData.val -= 1;

        // Create ecdsaData.
        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute opPoke.
        vm.broadcast(relay);
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Execute opChallenge.
        vm.broadcast(challenger);
        opScribe.opChallenge(schnorrData);
    }

    function _createFeeds(uint numberFeeds)
        internal
        returns (LibFeed.Feed[] memory)
    {
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](numberFeeds);

        // Note to not start with privKey=1. This is because the sum of public
        // keys would evaluate to:
        //   pubKeyOf(1) + pubKeyOf(2) + pubKeyOf(3) + ...
        // = pubKeyOf(3)               + pubKeyOf(3) + ...
        // Note that pubKeyOf(3) would be doubled. Doubling is not supported by
        // LibSecp256k1 as this would indicate a double-signing attack.
        uint privKey = 2;
        uint bloom;
        uint ctr;
        while (ctr != numberFeeds) {
            LibFeed.Feed memory feed = LibFeed.newFeed({privKey: privKey});

            // Check whether feed with id already created, if not create.
            if (bloom & (1 << feed.id) == 0) {
                bloom |= 1 << feed.id;

                feeds[ctr++] = feed;
            }

            privKey++;
        }

        return feeds;
    }
}
