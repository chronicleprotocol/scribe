pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSchnorrExtended} from "../libs/LibSchnorrExtended.sol";
//import {LibSecp256k1Extended} from "./libs/LibSecp256k1Extended.sol";

/**
 * @title Feed Script
 *
 * @dev
 */
contract Feed is Script {
    // @todo Load wallet...

    IScribe scribe = IScribe(address(0xcafe));

    function run() public {
        // Input : Same as legacy median, list of signed (value, age) tuples
        // Output: (pokeData, schnorrData) tuple with
        //          pokeData being the median of the list
        //          schnorrData being a single-signed Schnorr signature signing
        //                      the pokeData

        // 1. Verify input, same as legacy

        // 2. Compute median

        // 3. Sign via Schnorr
    }

    function signPokeData() public {
        // @todo Implement Feed::signedPokeData()
    }
}
