pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "test/utils/LibHelpers.sol";

// @audit Not production ready! Just for testing.
contract PokeScript is Script {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribe scribe =
        IScribe(address(0x5FbDB2315678afecb367f032d93F642f64180aa3));
    IScribeOptimistic opScribe =
        IScribeOptimistic(address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0));

    function run() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, 13);
        address[] memory feedAddrs = new address[](feeds.length);
        for (uint i; i < feedAddrs.length; i++) {
            feedAddrs[i] = feeds[i].pubKey.toAddress();
        }

        IScribe.SchnorrSignatureData memory schnorrSignatureData;
        schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, scribe.wat());

        bytes32 message = keccak256(
            abi.encode(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                abi.encodePacked(schnorrSignatureData.signers),
                schnorrSignatureData.signature,
                schnorrSignatureData.commitment,
                scribe.wat()
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(feeds[1].privKey, message);
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData;
        ecdsaSignatureData.v = v;
        ecdsaSignatureData.r = r;
        ecdsaSignatureData.s = s;

        // Costs:
        // 1. time: 149,050
        // 2. time: 131,950
        vm.startBroadcast();
        {
            scribe.poke(pokeData, schnorrSignatureData);
        }
        vm.stopBroadcast();

        // Costs:
        // 1. time: 97,285
        // 2. time: 80,057
        vm.startBroadcast();
        {
            opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
        }
        vm.stopBroadcast();
    }
}

/*
forge script \
    --broadcast \
    --rpc-url http://127.0.0.1:8545 \
     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
     script/Poke.s.sol:PokeScript
*/
