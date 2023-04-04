pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {Scribe} from "src/Scribe.sol";
import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "test/utils/LibHelpers.sol";

/**
 * @title Scribe Optimistic Benchmark Script
 *
 * @dev Usage:
 *      1. Open a new terminal start anvil via:
 *          $ anvil -b 1
 *      2. Deploy and setup contract via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "deployAndSetup()"
 *
 *      3. Execute opPoke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "opPoke()"
 */
contract ScribeOptimisticBenchmark is Script {
    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    ScribeOptimistic opScribe;

    // Numbers:
    // Deployment: 2,477,948
    function deployAndSetup() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Deploy contract.
        vm.broadcast(deployer);
        opScribe = new ScribeOptimistic();

        // Note to set the opChallengePeriod to a low value.
        vm.broadcast(deployer);
        opScribe.setOpChallengePeriod(1 seconds);

        // Create bar many feeds.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, opScribe.bar());

        // Create list of feeds' public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Create feeds' ECDSA signatures needed to lift them.
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

    // Numbers:
    // 1. execution: 90,140
    // 2. execution: 70,125
    // 3. execution: 53,025
    function opPoke() public {
        uint relayer = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));
        opScribe = ScribeOptimistic(payable(address(0x5FbDB2315678afecb367f032d93F642f64180aa3)));

        // Create bar many feeds.
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

        // Create schnorrSignatureData.
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
