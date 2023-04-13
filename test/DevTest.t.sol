pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Scribe_Optimized} from "src/Scribe_Optimized.sol";
import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

contract DevTest is Test {
    using LibHelpers for LibHelpers.Feed[];

    /*
    Scribe_Optimized private scribe;
    Scribe private scribeLeg;

    bytes32 internal FEED_LIFT_MESSAGE;

    LibHelpers.Feed[] internal feeds;

    function setUp() public {
        scribe = new Scribe_Optimized();
        scribeLeg = new Scribe();

        FEED_LIFT_MESSAGE = scribe.feedLiftMessage();

        // Create and lift bar many feeds.
        LibHelpers.Feed[] memory feeds_ = LibHelpers.makeFeeds(1, scribe.bar());
        for (uint i; i < feeds_.length; i++) {
            // Note to copy feed individually to prevent
            // "UnimplementedFeatureError" when compiling without --via-ir.
            feeds.push(feeds_[i]);

            // Lift the feed.
            scribe.lift(
                feeds_[i].pubKey,
                LibHelpers.makeECDSASignature(feeds_[i], FEED_LIFT_MESSAGE)
            );
            scribeLeg.lift(
                feeds_[i].pubKey,
                LibHelpers.makeECDSASignature(feeds_[i], FEED_LIFT_MESSAGE)
            );
        }
    }

    function test_decode() public {
        //address scribeAddr = address(scribe);
        //uint result;
        //assembly ("memory-safe") {
        //    let m := mload(0x40)
        //    mstore(m, 0xe5c5e9a300000000000000000000000000000000000000000000000000000000)
        //    mstore(add(m, 4), 0x20)
        //    mstore(add(m, 36), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
        //    let ok := call(gas(), scribeAddr, 0, m, 68, result, 32)
        //}

        // cast pretty-calldata $(cast calldata "decode(bytes)(uint)" 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) -o

        bytes memory blob = hex"01020403100aff";

        blob = abi.encodePacked(uint8(1));

        uint[] memory result = scribe.decode(blob);

        console2.log("result", result.length);
        for (uint i; i < result.length; i++) {
            console2.log("result[i]", result[i]);
        }
    }

    function test_verify() public {
        bytes32 message =
            hex"DEADffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        bytes32 signature =
            hex"C0FFEEffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        address commitment = address(0xb00b);

        bytes memory blob;
        blob = abi.encodePacked(uint8(1), uint8(0));

        IScribe.SchnorrSignatureData memory schnorrData =
            feeds.signSchnorrMessage(scribe, IScribe.PokeData(1, 1));

        scribe.verifySchnorrSignature_Optimized(
            message, signature, commitment, blob
        );

        scribeLeg.verifySchnorrSignature(message, schnorrData);
    }
    */
}
