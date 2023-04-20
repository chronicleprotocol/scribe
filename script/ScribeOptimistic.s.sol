pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title ScribeOptimistic Management Script
 *
 * @dev Usage:
 */
contract ScribeOptimisticScript is Script {
    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    function deploy() public returns (IScribeOptimistic) {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.startBroadcast(deployer);
        IScribeOptimistic opScribe = new ScribeOptimistic("ETH/USD");
        vm.stopBroadcast();

        return opScribe;
    }

    function setBar() public {}

    // ...
}
