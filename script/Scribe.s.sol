pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title Scribe Management Script
 */
abstract contract ScribeScript is Script {
    /// @dev Will be overwritten in Scribe instance's specific script.
    function deploy() public virtual;

    function poke(
        address self,
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrData memory schnorrData
    ) public {
        vm.broadcast();
        IScribe(self).poke(pokeData, schnorrData);
    }

    function setBar(address self, uint8 bar) public {
        vm.broadcast();
        IScribe(self).setBar(bar);
    }

    function lift(
        address self,
        LibSecp256k1.Point memory pubKey,
        IScribe.ECDSAData memory ecdsaData
    ) public {
        vm.broadcast();
        IScribe(self).lift(pubKey, ecdsaData);
    }

    function lift(
        address self,
        LibSecp256k1.Point[] memory pubKeys,
        IScribe.ECDSAData[] memory ecdsaDatas
    ) public {
        vm.broadcast();
        IScribe(self).lift(pubKeys, ecdsaDatas);
    }

    function drop(address self, uint feedIndex) public {
        vm.broadcast();
        IScribe(self).drop(feedIndex);
    }

    function drop(address self, uint[] memory feedIndexes) public {
        vm.broadcast();
        IScribe(self).drop(feedIndexes);
    }
}
