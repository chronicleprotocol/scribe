pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {Scribe} from "src/Scribe.sol";
import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "test/utils/LibHelpers.sol";

// @audit Not production ready! Just for testing.
contract DeployScript is Script {
    Scribe scribe;
    ScribeOptimistic opScribe;

    function run() public {
        vm.startBroadcast();
        {
            scribe = new Scribe();
            scribe.setBar(13);

            opScribe = new ScribeOptimistic();
            opScribe.setBar(13);
        }
        vm.stopBroadcast();

        // Create 13 feed privKey/pubKey tuples.
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, 13);

        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < pubKeys.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        vm.startBroadcast();
        {
            // @todo Fix lift. Needs ecdsa signed message.
            //scribe.lift(pubKeys);
            //opScribe.lift(pubKeys);
        }
        vm.stopBroadcast();
    }
}

/*
forge script \
    --broadcast \
    --rpc-url http://127.0.0.1:8545 \
     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
     script/Deploy.s.sol:DeployScript
*/
