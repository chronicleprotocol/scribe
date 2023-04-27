pragma solidity ^0.8.16;

// -- Test: Scribe --
//
// @todo Use deployment and maintanence scripts.

import {Scribe} from "src/Scribe.sol";
import {ScribeInspectable} from "./inspectable/ScribeInspectable.sol";
import {IScribe} from "src/IScribe.sol";

import {IScribeTest} from "./IScribeTest.sol";
import {IScribeInvariantTest} from "./invariants/IScribeInvariantTest.sol";
import {ScribeHandler} from "./invariants/ScribeHandler.sol";

contract ScribeTest is IScribeTest {
    function setUp() public {
        setUp(address(new Scribe("ETH/USD")));
    }
}

contract ScribeInvariantTest is IScribeInvariantTest {
    function setUp() public {
        setUp(
            address(new ScribeInspectable("ETH/USD")),
            address(new ScribeHandler())
        );
    }
}

// -- Test: Optimistic Scribe --

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
import {ScribeOptimisticInspectable} from
    "./inspectable/ScribeOptimisticInspectable.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {IScribeOptimisticTest} from "./IScribeOptimisticTest.sol";
import {IScribeOptimisticInvariantTest} from
    "./invariants/IScribeOptimisticInvariantTest.sol";
import {ScribeOptimisticHandler} from "./invariants/ScribeOptimisticHandler.sol";

contract ScribeOptimisticTest is IScribeOptimisticTest {
    function setUp() public {
        setUp(address(new ScribeOptimistic("ETH/USD")));
    }
}

contract ScribeOptimisticInvariantTest is IScribeOptimisticInvariantTest {
    function setUp() public {
        setUp(
            address(new ScribeOptimisticInspectable("ETH/USD")),
            address(new ScribeOptimisticHandler())
        );
    }
}

// -- Test: Libraries --

import {LibSecp256k1Test as LibSecp256k1Test_} from "./LibSecp256k1Test.sol";

contract LibSecp256k1Test is LibSecp256k1Test_ {}

import {LibSchnorrTest as LibSchnorrTest_} from "./LibSchnorrTest.sol";

contract LibSchnorrTest is LibSchnorrTest_ {}

import {LibBytesTest as LibBytesTest_} from "./LibBytesTest.sol";

contract LibBytesTest is LibBytesTest_ {}

import {LibSchnorrDataTest as LibSchnorrDataTest_} from
    "./LibSchnorrDataTest.sol";

contract LibSchnorrDataTest is LibSchnorrDataTest_ {}

// -- Test: EVM Requirements --

import {EVMTest} from "./EVMTest.sol";

contract EVMTest_ is EVMTest {}
