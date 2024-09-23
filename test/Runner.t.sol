// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// -- Test: Scribe --

import {Scribe} from "src/Scribe.sol";
import {ScribeInspectable} from "./inspectable/ScribeInspectable.sol";
import {IScribe} from "src/IScribe.sol";

import {IScribeTest} from "./IScribeTest.sol";
import {IScribeInvariantTest} from "./invariants/IScribeInvariantTest.sol";
import {ScribeHandler} from "./invariants/ScribeHandler.sol";

contract ScribeTest is IScribeTest {
    function setUp() public {
        setUp(address(new Scribe(address(this), "ETH/USD")));
    }
}

contract ScribeInvariantTest is IScribeInvariantTest {
    function setUp() public {
        setUp(
            address(new ScribeInspectable(address(this), "ETH/USD")),
            address(new ScribeHandler())
        );
    }
}

// -- Extensions

import {ScribeLST} from "src/extensions/ScribeLST.sol";
import {IScribeLSTTest} from "./extensions/IScribeLSTTest.sol";

contract ScribeLSTTest is IScribeLSTTest {
    function setUp() public {
        setUp(address(new ScribeLST(address(this), "ETH/USD")));
    }
}

// -- Test: Optimistic Scribe --

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {IScribeOptimisticTest} from "./IScribeOptimisticTest.sol";

contract ScribeOptimisticTest is IScribeOptimisticTest {
    function setUp() public {
        setUp(address(new ScribeOptimistic(address(this), "ETH/USD")));
    }
}

// -- Extensions

import {ScribeOptimisticLST} from "src/extensions/ScribeOptimisticLST.sol";
import {IScribeOptimisticLSTTest} from
    "./extensions/IScribeOptimisticLSTTest.sol";

contract ScribeOptimisticLSTTest is IScribeOptimisticLSTTest {
    function setUp() public {
        setUp(
            payable(address(new ScribeOptimisticLST(address(this), "ETH/USD")))
        );
    }
}

// -- Test: Libraries --

import {LibSecp256k1Test as LibSecp256k1Test_} from "./LibSecp256k1Test.sol";

contract LibSecp256k1Test is LibSecp256k1Test_ {}

import {LibSchnorrTest as LibSchnorrTest_} from "./LibSchnorrTest.sol";

contract LibSchnorrTest is LibSchnorrTest_ {}

// -- Test: EVM Requirements --

import {EVMTest} from "./EVMTest.sol";

contract EVMTest_ is EVMTest {}
