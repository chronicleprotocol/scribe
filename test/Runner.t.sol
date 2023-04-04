pragma solidity ^0.8.16;

/*//////////////////////////////////////////////////////////////
                  TEST: Scribe IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

import {Scribe} from "src/Scribe.sol";
import {IScribe} from "src/IScribe.sol";

import {IScribeTest} from "./IScribeTest.sol";
import {IScribeInvariantTest} from "./invariants/IScribeInvariantTest.sol";
import {ScribeHandler} from "./invariants/ScribeHandler.sol";
import {IScribeBenchmarkTest} from "./benchmarks/IScribeBenchmarkTest.sol";

contract ScribeTest is IScribeTest {
    function setUp() public {
        setUp(address(new Scribe()));
    }
}

contract ScribeInvariantTest is IScribeInvariantTest {
    function setUp() public {
        setUp(address(new Scribe()), address(new ScribeHandler()));
    }
}

contract ScribeBenchmarkTest is IScribeBenchmarkTest {
    function setUp() public {
        setUp(address(new Scribe()));
    }
}

/*//////////////////////////////////////////////////////////////
             TEST: Optimistic Scribe IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {IScribeOptimisticTest} from "./IScribeOptimisticTest.sol";
import {IScribeOptimisticInvariantTest} from
    "./invariants/IScribeOptimisticInvariantTest.sol";
import {ScribeOptimisticHandler} from "./invariants/ScribeOptimisticHandler.sol";
import {IScribeOptimisticBenchmarkTest} from
    "./benchmarks/IScribeOptimisticBenchmarkTest.sol";

contract ScribeOptimisticTest is IScribeOptimisticTest {
    function setUp() public {
        setUp(address(new ScribeOptimistic()));
    }
}

contract ScribeOptimisticInvariantTest is IScribeOptimisticInvariantTest {
    function setUp() public {
        setUp(
            address(new ScribeOptimistic()),
            address(new ScribeOptimisticHandler())
        );
    }
}

contract ScribeOptimisticBenchmarkTest is IScribeOptimisticBenchmarkTest {
    function setUp() public {
        setUp(address(new ScribeOptimistic()));
    }
}

/*//////////////////////////////////////////////////////////////
                    TEST: Secp256k1 LIBRARY
//////////////////////////////////////////////////////////////*/

import {LibSecp256k1Test} from "./LibSecp256k1Test.sol";
import {LibSecp256k1BenchmarkTest} from
    "./benchmarks/LibSecp256k1BenchmarkTest.sol";

contract Secp256k1Test is LibSecp256k1Test {}

contract Secp256k1BenchmarkTest is LibSecp256k1BenchmarkTest {}

/*//////////////////////////////////////////////////////////////
                     TEST: Schnorr LIBRARY
//////////////////////////////////////////////////////////////*/

/*//////////////////////////////////////////////////////////////
                   TEST: ecrecover INVARIANTS
//////////////////////////////////////////////////////////////*/

import {EcRecoverTest} from "./EcRecoverTest.sol";

contract EcRecoverDummyTest is EcRecoverTest {}
