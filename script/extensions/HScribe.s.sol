// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IToll} from "chronicle-std/toll/IToll.sol";

import {ChronicleHistorical_BASE_QUOTE_COUNTER as HScribe} from "src/extensions/HScribe.sol";
// @todo                    ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.

import {ScribeScript} from "../Scribe.s.sol";


/**
 * @notice hScribe Management Script
 */
contract HScribeScript is ScribeScript {
    /// @dev Deploys a new HScribe instance with `initialAuthed` being the address
    ///      initially auth'ed and a history size of `historySize`.
    ///      Note that zero address is kissed directly after deployment.
    function deploy(address initialAuthed, bytes32 wat, uint8 historySize) public {
        require(historySize != 0, "History size must not be zero");

        vm.startBroadcast();
        require(msg.sender == initialAuthed, "Deployer must be initial auth'ed");
        address deployed = address(new HScribe(initialAuthed, wat, historySize));
        IToll(deployed).kiss(address(0));
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
    }

    /// @inheritdoc ScribeScript
    ///
    /// @custom:disabled Use `deploy(address,bytes32,uint8)` instead.
    function deploy(address, bytes32) public pure override(ScribeScript) {
        revert("Function not implemented");
    }
}
