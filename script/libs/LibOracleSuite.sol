// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

/**
 * @notice LibOracleSuite
 *
 * @dev Wrapper library for oracle-suite's `schnorr` cli tool.
 *
 *      Expects `schnorr` binary to be in the `bin/` directory.
 *
 *      For more info, see https://github.com/chronicleprotocol/oracle-suite.
 */
library LibOracleSuite {
    Vm private constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    /// @dev Signs message `message` via set of private keys `privKeys`.
    ///
    ///      Signed via:
    ///      ```bash
    ///      ./bin/schnorr sign <message> <privKeys...>
    ///      ```
    function sign(uint[] memory privKeys, bytes32 message)
        internal
        returns (uint, address)
    {
        string[] memory inputs = new string[](3 + privKeys.length);
        inputs[0] = "bin/schnorr";
        inputs[1] = "sign";
        inputs[2] = vm.toString(message);
        for (uint i; i < privKeys.length; i++) {
            inputs[3 + i] = vm.toString(bytes32(privKeys[i]));
        }

        uint[2] memory result = abi.decode(vm.ffi(inputs), (uint[2]));

        uint signature = result[0];
        address commitment = address(uint160(result[1]));

        return (signature, commitment);
    }

    /// @dev Constructs poke message for `wat` with value `val` and age `age`.
    ///
    ///      Constructed via:
    ///      ```bash
    ///      ./bin/schnorr construct-poke-message <wat> <val> <age>
    ///      ```
    function constructPokeMessage(bytes32 wat, uint128 val, uint32 age)
        internal
        returns (bytes32)
    {
        string[] memory inputs = new string[](5);
        inputs[0] = "bin/schnorr";
        inputs[1] = "construct-poke-message";
        inputs[2] = _bytes32ToString(wat);
        inputs[3] = vm.toString(val);
        inputs[4] = vm.toString(age);

        return abi.decode(vm.ffi(inputs), (bytes32));
    }

    // -- Private Helpers --

    // Copied from https://ethereum.stackexchange.com/a/59335/114758.
    function _bytes32ToString(bytes32 _bytes32)
        private
        pure
        returns (string memory)
    {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
