pragma solidity ^0.8.16;

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibDissig} from "./LibDissig.sol";

library LibSecp256k1Extended {
    function derivePublicKey(uint privKey)
        internal
        returns (LibSecp256k1.Point memory)
    {
        // @todo Use a native implementation to save ffi overhead.
        return LibDissig.toPoint(privKey);
    }

    /*//////////////////////////////////////////////////////////////
                             JACOBIAN POINT
    //////////////////////////////////////////////////////////////*/

    function multiply(LibSecp256k1.JacobianPoint memory self, uint scalar)
        internal
        view
        returns (LibSecp256k1.JacobianPoint memory)
    {}
}
