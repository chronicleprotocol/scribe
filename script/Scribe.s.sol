pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

/**
 * @title Scribe Management Script
 *
 * @dev Usage:
 */
contract ScribeScript is Script {
    /// @dev Anvil's default mnemonic.
    string internal constant ANVIL_MNEMONIC =
        "test test test test test test test test test test test junk";

    function deploy() public returns (IScribe) {
        uint deployer = vm.deriveKey(ANVIL_MNEMONIC, uint32(0));

        vm.startBroadcast(deployer);
        IScribe scribe = new Scribe("ETH/USD");
        vm.stopBroadcast();

        return scribe;
    }

    function setBar() public {}

    // ...
}
