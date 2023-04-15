pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

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

    /// @dev Returns the point [scalar]G.
    ///
    ///      Computed via:
    ///      ```bash
    ///      ./bin/dissig --scribe                     \
    ///                   --scribe-cmd=pointFromScalar \
    ///                   --scribe-scalar=<scalar>
    ///      ```
    function toPoint(uint scalar)
        internal
        returns (LibSecp256k1.Point memory)
    {
        string[] memory inputs = new string[](4);
        inputs[0] = "bin/dissig";
        inputs[1] = "--scribe";
        inputs[2] = "--scribe-cmd=pointFromScalar";
        inputs[3] = string.concat("--scribe-scalar=", vm.toString(scalar));

        uint[2] memory coordinates = abi.decode(vm.ffi(inputs), (uint[2]));
        return LibSecp256k1.Point({x: coordinates[0], y: coordinates[1]});
    }

    /// @dev Returns the sum of the points generated from the scalars.
    ///
    ///      Computed via:
    ///      ```bash
    ///      ./bin/dissig --scribe                      \
    ///                   --scribe-cmd=pointAggregation \
    ///                   --scribe-scalars=<scalarA>    \
    ///                   --scribe-scalars=<scalarB>
    ///      ````
    function aggregateToPoint(uint scalarA, uint scalarB)
        internal
        returns (LibSecp256k1.Point memory)
    {
        string[] memory inputs = new string[](5);
        inputs[0] = "bin/dissig";
        inputs[1] = "--scribe";
        inputs[2] = "--scribe-cmd=pointAggregation";
        inputs[3] = string.concat("--scribe-scalars=", vm.toString(scalarA));
        inputs[4] = string.concat("--scribe-scalars=", vm.toString(scalarB));

        uint[2] memory coordinates = abi.decode(vm.ffi(inputs), (uint[2]));
        return LibSecp256k1.Point({x: coordinates[0], y: coordinates[1]});
    }
}
