pragma solidity ^0.8.16;

/*//////////////////////////////////////////////////////////////
                  TEST: SCRIBE IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

import {Scribe} from "src/Scribe.sol";
import {IScribe} from "src/IScribe.sol";
import {IScribeAuth} from "src/IScribeAuth.sol";

import {IScribeTest} from "./IScribeTest.sol";
import {IScribeAuthTest} from "./IScribeAuthTest.sol";
import {IScribeInvariantTest} from "./invariants/IScribeInvariantTest.sol";

contract ScribeTest is IScribeTest {
    function setUp() public {
        setUp(address(new Scribe()));
    }
}

contract ScribeAuthTest is IScribeAuthTest {
    function setUp() public {
        setUp(address(new Scribe()));
    }
}

contract ScribeInvariantTest is IScribeInvariantTest {
    function setUp() public {
        setUp(address(new Scribe()));
    }
}

/*//////////////////////////////////////////////////////////////
             TEST: OPTIMISTIC SCRIBE IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

import {ScribeOptimistic} from "src/ScribeOptimistic.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "src/IScribeOptimisticAuth.sol";

import {IScribeOptimisticTest} from "./IScribeOptimisticTest.sol";
import {IScribeOptimisticAuthTest} from "./IScribeOptimisticAuthTest.sol";
//import {IScribeInvariantTest} from "./invariants/IScribeInvariantTest.sol";

contract ScribeOptimisticTest is IScribeOptimisticTest {
    function setUp() public {
        setUp(address(new ScribeOptimistic()));
    }
}

contract ScribeOptimisticAuthTest is IScribeOptimisticAuthTest {
    function setUp() public {
        setUp(address(new ScribeOptimistic()));
    }
}
