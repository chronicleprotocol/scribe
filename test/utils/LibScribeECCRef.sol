pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title LibScribeECCRef
 *
 * @dev Wrapper library for the `scribe-ecc-ref` cli tool.
 *
 *      Expects `scribe-ecc-ref` binary to be in the `bin/` directory.
 */
library LibScribeECCRef {
    Vm private constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    /// @dev Runs `scribe-ecc-ref secp256k1 scalarMultiplication <scalar>`.
    function scalarMultiplication(uint scalar)
        internal
        returns (LibSecp256k1.Point memory)
    {
        string[] memory inputs = new string[](4);
        inputs[0] = "bin/scribe-ecc-ref";
        inputs[1] = "secp256k1";
        inputs[2] = "scalarMultiplication";
        inputs[3] = vm.toString(scalar);

        uint[2] memory coordinates = abi.decode(vm.ffi(inputs), (uint[2]));
        return LibSecp256k1.Point(coordinates[0], coordinates[1]);
    }

    /// @dev Runs `scribe-ecc-ref secp256k1 pointAddition <points...>`.
    function pointAddition(LibSecp256k1.Point[] memory points)
        internal
        returns (LibSecp256k1.Point memory)
    {
        string[] memory inputs = new string[](3 + 2 * points.length);
        inputs[0] = "bin/scribe-ecc-ref";
        inputs[1] = "secp256k1";
        inputs[2] = "pointAddition";

        uint inputsCtr = 3;
        for (uint i; i < points.length; i++) {
            inputs[inputsCtr++] = vm.toString(points[i].x);
            inputs[inputsCtr++] = vm.toString(points[i].y);
        }

        uint[2] memory coordinates = abi.decode(vm.ffi(inputs), (uint[2]));
        return LibSecp256k1.Point(coordinates[0], coordinates[1]);
    }

    /// @dev Runs `scribe-ecc-ref schnorr sign <private key> <message hash>`.
    function sign(uint privKey, bytes32 messageHash)
        internal
        returns (bytes32)
    {
        string[] memory inputs = new string[](5);
        inputs[0] = "bin/scribe-ecc-ref";
        inputs[1] = "schnorr";
        inputs[2] = "sign";
        inputs[3] = vm.toString(privKey);
        inputs[4] = vm.toString(messageHash);

        bytes32 signature = abi.decode(vm.ffi(inputs), (bytes32));
        return signature;
    }
}
