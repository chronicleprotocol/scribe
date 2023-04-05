pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "test/utils/LibHelpers.sol";

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
 *      3. Lift feeds via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()"
 *
 *      4. Poke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()"
 *
 *      5. opPoke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "opPoke()"
 *
 *      Note to (op)Poke more than once to get realistic gas costs.
 *      During the first execution the storage slots are empty.
 */
contract ScribeOptimisticBenchmark is Script {
    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    ScribeOptimistic opScribe = ScribeOptimistic(
        payable(address(0x5FbDB2315678afecb367f032d93F642f64180aa3))
    );

    function deploy() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.broadcast(deployer);
        opScribe = new ScribeOptimistic();

        // Note to set opChallengePeriod to small value.
        vm.broadcast(deployer);
        opScribe.setOpChallengePeriod(1 seconds);
    }

    function liftFeeds() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Create bar many feeds.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, opScribe.bar());

        // Create list of feeds' public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Create feeds' ECDSA signatures in order to lift them.
        IScribe.ECDSASignatureData[] memory sigs =
            new IScribe.ECDSASignatureData[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            sigs[i] = LibHelpers.makeECDSASignature(
                feeds[i], opScribe.feedLiftMessage()
            );
        }

        // Lift feeds.
        vm.broadcast(deployer);
        opScribe.lift(pubKeys, sigs);
    }

    function poke() public {
        uint relayer = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

        // Create bar many feeds.
        // Note to create same set of feeds as lifted.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, opScribe.bar());

        // Create list of feeds' public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Create PokeData.
        // Note to use max value for val and age to have highest possible gas
        // costs.
        IScribe.PokeData memory pokeData =
            IScribe.PokeData({val: type(uint128).max, age: type(uint32).max});

        // Create SchnorrSignatureData.
        IScribe.SchnorrSignatureData memory schnorrData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, opScribe.wat());

        // Poke.
        vm.broadcast(relayer);
        opScribe.poke(pokeData, schnorrData);
    }

    function opPoke() public {
        uint relayer = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

        // Create bar many feeds.
        // Note to create same set of feeds as lifted.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, opScribe.bar());

        // Create list of feeds' public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Create PokeData.
        // Note to use max value for val and age to have highest possible gas
        // costs.
        IScribe.PokeData memory pokeData =
            IScribe.PokeData({val: type(uint128).max, age: type(uint32).max});

        // Create SchnorrSignatureData.
        IScribe.SchnorrSignatureData memory schnorrData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, opScribe.wat());

        // Create ECDSASignatureData.
        IScribe.ECDSASignatureData memory ecdsaData = LibHelpers
            .makeECDSASignature(feeds[0], pokeData, schnorrData, opScribe.wat());

        // Execute opPoke.
        vm.broadcast(relayer);
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }
}
