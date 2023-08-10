// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

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
 *      3. Set bar via:
 *          $ BAR=10 # Note to update to appropriate value
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig $(cast calldata "setBar(uint8)" $BAR)
 *
 *      4. Lift feeds via:
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()"
 *
 *      5. Poke via:
 *          $ forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()"
 *
 *      Note to poke more than once to get realistic gas costs.
 *      During the first execution the storage slots are empty.
 */
contract ScribeBenchmark is Script {
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    Scribe scribe = Scribe(address(0x5FbDB2315678afecb367f032d93F642f64180aa3));

    function deploy() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.broadcast(deployer);
        scribe = new Scribe(vm.addr(deployer), "ETH/USD");
    }

    function setBar(uint8 bar) public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.broadcast(deployer);
        scribe.setBar(bar);
    }

    function liftFeeds() public {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        // Create bar many feeds.
        LibFeed.Feed[] memory feeds = _createFeeds(scribe.bar());

        // Create list of feeds' public keys and ECDSA signatures.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        IScribe.ECDSAData[] memory sigs = new IScribe.ECDSAData[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
            sigs[i] = feeds[i].signECDSA(scribe.feedRegistrationMessage());
        }

        // Lift feeds.
        vm.broadcast(deployer);
        scribe.lift(pubKeys, sigs);
    }

    function poke() public {
        uint relay = vm.deriveKey(ANVIL_MNEMONIC, uint32(1));

        // Create bar many feeds.
        LibFeed.Feed[] memory feeds = _createFeeds(scribe.bar());

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
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        // Execute poke.
        vm.broadcast(relay);
        scribe.poke(pokeData, schnorrData);
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
