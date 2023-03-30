pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "src/IScribeOptimisticAuth.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

//import {ScribeOptimisticHandler} from "./ScribeOptimisticHandler.sol";

abstract contract IScribeOptimisticInvariantTest is Test {

}
