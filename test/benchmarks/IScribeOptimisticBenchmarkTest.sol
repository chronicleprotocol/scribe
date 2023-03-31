pragma solidity ^0.8.16;

import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "src/IScribeOptimisticAuth.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeBenchmarkTest} from "./IScribeBenchmarkTest.sol";

import {LibHelpers} from "../utils/LibHelpers.sol";

abstract contract IScribeOptimisticBenchmarkTest is IScribeBenchmarkTest {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeOptimistic opScribe;

    IScribeOptimistic.ECDSASignatureData ecdsaSignatureData;

    function setUp(address scribe_) internal override(IScribeBenchmarkTest) {
        super.setUp(scribe_);

        opScribe = IScribeOptimistic(scribe_);

        ecdsaSignatureData = LibHelpers.makeECDSASignature(
            feeds[0], pokeData, schnorrSignatureData, WAT
        );
    }

    function testBenchmark_opPoke() public {
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }
}
