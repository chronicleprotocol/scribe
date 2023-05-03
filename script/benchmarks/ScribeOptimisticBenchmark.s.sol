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
 *      3. Lift feeds via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()"
 *
 *      4. Set opChallengePeriod via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "setOpChallengePeriod()"
 *
 *      4. Poke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()"
 *
 *      5. opPoke via:
 *          $ forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "opPoke()"
 *
 *      Note to (op)Poke more than once to get realistic gas costs.
 *      During the first execution the storage slots are empty.
 *
 * @dev Results:
 *      - Deployment:
 *          3,545,416
 *
 *      - Lift 2 feeds:
 *          181,882
 *
 *      - Set opChallengePeriod:
 *          55,770
 *
 *      - opPoke 1. time:
 *          68,381
 *
 *      - opPoke 2. time:
 *          54,252
 *
 *      - opPoke 3. time:
 *          54,252
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
        opScribe = new ScribeOptimistic("ETH/USD");
    }

    function setOpChallengePeriod() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Note to set opChallengePeriod to small value.
        vm.broadcast(deployer);
        opScribe.setOpChallengePeriod(1 seconds);
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
            sigs[i] = feeds[i].signECDSA(opScribe.watMessage());
        }

        // Lift feeds.
        vm.broadcast(deployer);
        opScribe.lift(pubKeys, sigs);
    }

    function poke() public {
        uint relayer = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

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
        vm.broadcast(relayer);
        opScribe.poke(pokeData, schnorrData);
    }

    function opPoke() public {
        uint relayer = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

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
        vm.broadcast(relayer);
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function _createFeeds(uint amount)
        internal
        pure
        returns (LibFeed.Feed[] memory)
    {
        uint startPrivKey = 2;

        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](amount);
        for (uint i; i < amount; i++) {
            feeds[i] = LibFeed.newFeed({
                privKey: startPrivKey + i,
                index: uint8(i + 1)
            });
        }

        return feeds;
    }
}
