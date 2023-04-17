pragma solidity ^0.8.16;

/*//////////////////////////////////////////////////////////////
                  TEST: Scribe IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

// @todo Use deployment and maintanence scripts.

import {Scribe_Optimized as Scribe} from "src/Scribe_Optimized.sol";
import {IScribe_Optimized as IScribe} from "src/IScribe_Optimized.sol";

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
        setUp(address(new Scribe("ETH/USD")), address(new ScribeHandler()));
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

/*//////////////////////////////////////////////////////////////
                    TEST: Secp256k1 LIBRARY
//////////////////////////////////////////////////////////////*/

import {LibSecp256k1Test} from "./LibSecp256k1Test.sol";

contract LibSecp256k1Test_ is LibSecp256k1Test {}

/*//////////////////////////////////////////////////////////////
                     TEST: Schnorr LIBRARY
//////////////////////////////////////////////////////////////*/

/*//////////////////////////////////////////////////////////////
                      TEST: Bytes LIBRARY
//////////////////////////////////////////////////////////////*/

import {LibBytesTest} from "./LibBytesTest.sol";

contract LibBytesTest_ is LibBytesTest {}

/*//////////////////////////////////////////////////////////////
                   TEST: ecrecover INVARIANTS
//////////////////////////////////////////////////////////////*/

import {EcRecoverTest} from "./EcRecoverTest.sol";

contract EcRecoverTest_ is EcRecoverTest {}
