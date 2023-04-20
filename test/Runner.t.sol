pragma solidity ^0.8.16;

//------------------------------------------------------------------------------
// Test: Scribe
//
// @todo Use deployment and maintanence scripts.

import {Scribe} from "src/Scribe.sol";
import {IScribe} from "src/IScribe.sol";

import {IScribeTest} from "./IScribeTest.sol";
import {IScribeInvariantTest} from "./invariants/IScribeInvariantTest.sol";
import {ScribeHandler} from "./invariants/ScribeHandler.sol";

contract ScribeTest is IScribeTest {
    function setUp() public {
        setUp(address(new Scribe("ETH/USD")));
    }
}

/*
contract ScribeInvariantTest is IScribeInvariantTest {
    function setUp() public {
        setUp(address(new Scribe("ETH/USD")), address(new ScribeHandler()));
    }
}
*/

//------------------------------------------------------------------------------
// Test: Optimistic Scribe

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
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

/*
contract ScribeOptimisticInvariantTest is IScribeOptimisticInvariantTest {
    function setUp() public {
        setUp(
            address(new ScribeOptimistic("ETH/USD")),
            address(new ScribeOptimisticHandler())
        );
    }
}
*/

//------------------------------------------------------------------------------
// Test: Secp256k1 Libraries

import {LibSecp256k1Test} from "./LibSecp256k1Test.sol";
import {LibSecp256k1ExtendedTest} from "./LibSecp256k1ExtendedTest.sol";

contract LibSecp256k1Test_ is LibSecp256k1Test {}

contract LibSecp256k1ExtendedTest_ is LibSecp256k1ExtendedTest {}

//------------------------------------------------------------------------------
// Test: Schnorr Libraries

//------------------------------------------------------------------------------
// Test: Bytes Library

import {LibBytesTest} from "./LibBytesTest.sol";

contract LibBytesTest_ is LibBytesTest {}

//------------------------------------------------------------------------------
// Test: EVM Assumptions

import {EcRecoverTest} from "./EcRecoverTest.sol";

contract EcRecoverTest_ is EcRecoverTest {}
