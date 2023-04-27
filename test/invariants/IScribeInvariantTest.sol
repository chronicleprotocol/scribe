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
        // Get scribe's pokeData before the execution.
        IScribe.PokeData memory beforePokeData = handler.scribe_lastPokeData();

        // Get scribe's current pokeData.
        IScribe.PokeData memory currentPokeData;
        currentPokeData = scribe.inspectable_pokeData();

        if (beforePokeData.age != currentPokeData.age) {
            assertTrue(beforePokeData.age < currentPokeData.age);
        } else {
            assertEq(beforePokeData.age, currentPokeData.age);
        }
    }

    function invariant_poke_PokeTimestampIsOnlyMutatedToCurrentTimestamp()
        public
    {
        // Get scribe's pokeData before the execution.
        IScribe.PokeData memory beforePokeData = handler.scribe_lastPokeData();

        // Get scribe's current pokeData.
        IScribe.PokeData memory currentPokeData;
        currentPokeData = scribe.inspectable_pokeData();

        if (beforePokeData.age != currentPokeData.age) {
            assertEq(currentPokeData.age, uint32(block.timestamp));
        }
    }

    // -- PubKeys --

    function invariant_pubKeys_AtIndexZeroIsZeroPoint() public {
        assertTrue(scribe.inspectable_pubKeys(0).isZeroPoint());
    }

    mapping(bytes32 => bool) private pubKeyFilter;

    function invariant_pubKeys_NonZeroPubKeyExistsAtMostOnce() public {
        LibSecp256k1.Point[] memory pubKeys = scribe.inspectable_pubKeys();
        for (uint i; i < pubKeys.length; i++) {
            if (pubKeys[i].isZeroPoint()) continue;

            bytes32 id = keccak256(abi.encodePacked(pubKeys[i].x, pubKeys[i].y));

            assertFalse(pubKeyFilter[id]);
            pubKeyFilter[id] = true;
        }
    }

    function invariant_pubKeys_LengthIsStrictlyMonotonicallyIncreasing()
        public
    {
        uint lastLen = handler.scribe_lastPubKeysLength();
        uint currentLen = scribe.inspectable_pubKeys().length;

        assertTrue(lastLen <= currentLen);
    }

    function invariant_pubKeys_ZeroPointIsNeverAddedAsPubKey() public {
        uint lastLen = handler.scribe_lastPubKeysLength();

        LibSecp256k1.Point[] memory pubKeys;
        pubKeys = scribe.inspectable_pubKeys();

        if (lastLen != pubKeys.length) {
            assertFalse(pubKeys[pubKeys.length - 1].isZeroPoint());
        }
    }

    // -- Feeds --

    function invariant_feeds_ImageIsZeroToLengthOfPubKeys() public {
        address[] memory feedAddrs = handler.ghost_feedAddresses();
        uint pubKeysLen = scribe.inspectable_pubKeys().length;

        for (uint i; i < feedAddrs.length; i++) {
            uint index = scribe.inspectable_feeds(feedAddrs[i]);

            assertTrue(index < pubKeysLen);
        }
    }

    function invariant_feeds_LinkToTheirPublicKeys() public {
        address[] memory feedAddrs = handler.ghost_feedAddresses();

        LibSecp256k1.Point[] memory pubKeys;
        pubKeys = scribe.inspectable_pubKeys();

        LibSecp256k1.Point memory pubKey;
        for (uint i; i < feedAddrs.length; i++) {
            uint index = scribe.inspectable_feeds(feedAddrs[i]);

            pubKey = pubKeys[index];
            if (!pubKey.isZeroPoint()) {
                assertEq(pubKey.toAddress(), feedAddrs[i]);
            }
        }
    }

    // -- Bar --

    function invariant_bar_IsNeverZero() public {
        assertTrue(scribe.bar() != 0);
    }
}
