// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {ScribeInspectable} from "../inspectable/ScribeInspectable.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeHandler} from "./ScribeHandler.sol";

abstract contract IScribeInvariantTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    ScribeInspectable private scribe;
    ScribeHandler private handler;

    function setUp(address scribe_, address handler_) internal virtual {
        scribe = ScribeInspectable(scribe_);
        handler = ScribeHandler(handler_);

        // Toll address(this).
        scribe.kiss(address(this));

        // Make handler auth'ed.
        scribe.rely(address(handler));

        // Finish handler initialization.
        // Needs to be done after handler is auth'ed.
        handler.init(scribe_);

        // Set handler as target contract.
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: _targetSelectors()})
        );
        targetContract(address(handler));
    }

    function _targetSelectors() internal virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = ScribeHandler.warp.selector;
        selectors[1] = ScribeHandler.poke.selector;
        selectors[2] = ScribeHandler.setBar.selector;
        selectors[3] = ScribeHandler.lift.selector;
        selectors[4] = ScribeHandler.drop.selector;

        return selectors;
    }

    // -- Poke --

    function invariant_poke_PokeTimestampsAreStrictlyMonotonicallyIncreasing()
        public
    {
        // Get scribe's pokeData before execution.
        IScribe.PokeData memory beforePokeData = handler.scribe_lastPokeData();

        // Get scribe's current pokeData.
        IScribe.PokeData memory currentPokeData;
        currentPokeData = scribe.inspectable_pokeData();

        assertTrue(beforePokeData.age <= currentPokeData.age);
    }

    // -- PubKeys --

    function invariant_pubKeys_IndexedViaFeedId() public {
        LibSecp256k1.Point memory pubKey;
        uint8 feedId;

        for (uint i; i < 256; i++) {
            pubKey = scribe.inspectable_pubKeys(uint8(i));
            feedId = uint8(uint(uint160(pubKey.toAddress())) >> 152);

            assertTrue(pubKey.isZeroPoint() || i == feedId);
        }
    }

    function invariant_pubKeys_CannotIndexOutOfBoundsViaUint8Index()
        public
        view
    {
        for (uint i; i <= type(uint8).max; i++) {
            // Should not revert.
            scribe.inspectable_pubKeys(uint8(i));
        }
    }

    // -- Bar --

    function invariant_bar_IsNeverZero() public {
        assertTrue(scribe.bar() != 0);
    }
}
