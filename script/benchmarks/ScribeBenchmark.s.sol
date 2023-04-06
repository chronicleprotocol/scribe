pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "test/utils/LibHelpers.sol";

/**
 * @notice Scribe Benchmark Script
 *
 * @dev Usage:
 *      1. Open new terminal and start anvil via:
 *          $ anvil -b 1
 *
 *      2. Deploy contract via:
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "deploy()"
 *
 *      3. Lift feeds via:
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()"
 *
 *      4. Poke via:
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()"
 *
 *      Note to poke more than once to get realistic gas costs.
 *      During the first execution the storage slots are empty.
 */
contract ScribeBenchmark is Script {
    using LibHelpers for LibHelpers.Feed[];

    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    Scribe scribe = Scribe(address(0x5FbDB2315678afecb367f032d93F642f64180aa3));

    function deploy() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.broadcast(deployer);
        scribe = new Scribe();
    }

    function liftFeeds() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Create bar many feeds.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, scribe.bar());

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
                feeds[i], scribe.feedLiftMessage()
            );
        }

        // Lift feeds.
        vm.broadcast(deployer);
        scribe.lift(pubKeys, sigs);
    }

    function poke() public {
        uint relayer = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

        // Create bar many feeds.
        // Note to create same set of feeds as lifted.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, scribe.bar());

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
        IScribe.SchnorrSignatureData memory schnorrData;
        schnorrData = feeds.signSchnorrMessage(scribe, pokeData);

        // Poke.
        vm.broadcast(relayer);
        scribe.poke(pokeData, schnorrData);
    }
}
