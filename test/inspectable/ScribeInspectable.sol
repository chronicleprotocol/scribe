// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Scribe} from "src/Scribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

contract ScribeInspectable is Scribe {
    constructor(address initialAuthed, bytes32 wat_)
        Scribe(initialAuthed, wat_)
    {}

    /*
    function inspectable_pokeData() public view returns (PokeData memory) {
        return _pokeData;
    }

    function inspectable_pubKeys()
        public
        view
        returns (LibSecp256k1.Point[] memory)
    {
        return _pubKeys;
    }

    function inspectable_pubKeys(uint index)
        public
        view
        returns (LibSecp256k1.Point memory)
    {
        return _unsafeLoadPubKeyAt(index);
    }

    function inspectable_feeds(address addr) public view returns (uint) {
        return _feeds[addr];
    }
    */
}
