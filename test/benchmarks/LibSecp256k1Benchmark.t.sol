pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibScribeECCRef} from "../utils/LibScribeECCRef.sol";

contract LibSecp256k1Benchmark is Test {

    // @todo Use solidity-generators library.
    function test_gas_aggregate() public pure {

    }
}
