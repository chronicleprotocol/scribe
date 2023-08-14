// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {console2} from "forge-std/console2.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title LibRandom
 *
 * @notice Library providing access to cryptographically sound randomness
 *
 * @dev Randomness is sourced from cast's `new wallet` command.
 */
library LibRandom {
    Vm private constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    /// @dev Returns 256 bit of cryptographically sound randomness.
    function readUint() internal returns (uint) {
        string[] memory inputs = new string[](3);
        inputs[0] = "cast";
        inputs[1] = "wallet";
        inputs[2] = "new";

        bytes memory result = vm.ffi(inputs);

        // Note that while parts of `cast wallet new` output is constant, it
        // always contains the new wallet's private key and is therefore unique.
        //
        // Note that cast is trusted to create cryptographically secure wallets.
        return uint(keccak256(result));
    }
}
