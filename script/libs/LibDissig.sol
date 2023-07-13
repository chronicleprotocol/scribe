pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {console2} from "forge-std/console2.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title LibDissig
 *
 * @dev Wrapper library for the `dissig` cli tool.
 *
 *      Expects `dissig` binary to be in the `bin/` directory.
 *
 *      For more info, see https://github.com/chronicleprotocol/dissig.
 */
library LibDissig {
    Vm private constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    /// @dev Signs message `message` via set of private keys `privKeys`.
    ///
    ///      Signed via:
    ///      ```bash
    ///      ./bin/dissig                      \
    ///         --scribe                       \
    ///         --scribe-cmd=sign              \
    ///         --scribe-message=<message>     \
    ///         --scribe-privKeys=<privKey[0]> \
    ///         --scribe-privKeys=<privKey[1]> |
    ///         ...
    ///      ```
    function sign(uint[] memory privKeys, bytes32 message)
        internal
        returns (uint, address)
    {
        string[] memory inputs = new string[](4 + privKeys.length);
        inputs[0] = "bin/dissig";
        inputs[1] = "--scribe";
        inputs[2] = "--scribe-cmd=sign";
        inputs[3] = string.concat("--scribe-message=", vm.toString(message));
        for (uint i; i < privKeys.length; i++) {
            inputs[4 + i] = string.concat(
                "--scribe-privKeys=", vm.toString(bytes32(privKeys[i]))
            );
        }

        uint[2] memory result = abi.decode(vm.ffi(inputs), (uint[2]));

        uint signature = result[0];
        address commitment = address(uint160(result[1]));

        return (signature, commitment);
    }
}
