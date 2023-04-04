pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "../utils/LibHelpers.sol";

abstract contract IScribeBenchmarkTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribe scribe;

    bytes32 WAT;

    LibHelpers.Feed[] feeds;

    IScribe.PokeData pokeData;
    IScribe.SchnorrSignatureData schnorrSignatureData;

    function setUp(address scribe_) internal virtual {
        scribe = IScribe(scribe_);

        // Cache wat constant.
        WAT = scribe.wat();

        // Create and whitelist bar many feeds.
        LibHelpers.Feed[] memory feeds_ = LibHelpers.makeFeeds(1, scribe.bar());
        for (uint i; i < feeds_.length; i++) {
            scribe.lift(
                feeds_[i].pubKey,
                LibHelpers.makeECDSASignature(
                    feeds_[i], scribe.feedLiftMessage()
                )
            );

            // Note to copy feed individually to prevent
            // "UnimplementedFeatureError" when compiling without --via-ir.
            feeds.push(feeds_[i]);
        }

        // Toll address(this).
        IToll(address(scribe)).kiss(address(this));

        // Set pokeData and corresponding schnorrSignatureData.
        pokeData =
            IScribe.PokeData({val: type(uint128).max, age: type(uint32).max});
        schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);
    }

    function testBenchmark_poke() public {
        scribe.poke(pokeData, schnorrSignatureData);
    }
}
