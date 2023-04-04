pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {Scribe} from "src/Scribe.sol";
import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {ScribeHandler} from "./ScribeHandler.sol";

abstract contract IScribeInvariantTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribe private scribe;
    ScribeHandler private handler;

    function setUp(address scribe_, address handler_) internal virtual {
        scribe = IScribe(scribe_);
        handler = ScribeHandler(handler_); //new ScribeHandler(scribe_);

        // Toll address(this).
        IToll(address(scribe)).kiss(address(this));

        // Make handler auth'ed.
        IAuth(address(scribe)).rely(address(handler));

        // Finish handler initialization.
        // Needs to be done after handler is auth'ed.
        handler.init(scribe_);

        // Set handler as target contract.
        bytes4[] memory selectors = _targetSelectors();
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
        targetContract(address(handler));
    }

    function _targetSelectors() internal virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = ScribeHandler.warp.selector;
        selectors[1] = ScribeHandler.poke.selector;
        selectors[2] = ScribeHandler.pokeFaulty.selector;
        selectors[3] = ScribeHandler.setBar.selector;
        selectors[4] = ScribeHandler.lift.selector;
        selectors[5] = ScribeHandler.drop.selector;

        return selectors;
    }

    /*//////////////////////////////////////////////////////////////
                   INVARIANTS: READ & PEEK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function invariant_read_OnlyFailsIf_NoPokeYetOrLastPokeWasZero() public {
        try scribe.read() returns (uint) {}
        catch {
            IScribe.PokeData[] memory pokeDatas = handler.ghost_pokeDatas();

            uint len = pokeDatas.length;
            if (len != 0) {
                IScribe.PokeData memory lastPokeData = pokeDatas[len - 1];

                assertEq(lastPokeData.val, 0);
            }
        }
    }

    function invariant_read_ReturnsTheLastPokedValue() public {
        try scribe.read() returns (uint val) {
            IScribe.PokeData[] memory pokeDatas = handler.ghost_pokeDatas();

            uint len = pokeDatas.length;
            assertTrue(len != 0); // Otherwise read should revert.

            IScribe.PokeData memory lastPokeData = pokeDatas[len - 1];
            assertEq(val, lastPokeData.val);
        } catch {}
    }

    function invariant_peek_OnlyReturnsFalseIf_NoPokeYetOrLastPokeWasZero()
        public
    {
        (, bool ok) = scribe.peek();
        if (!ok) {
            IScribe.PokeData[] memory pokeDatas = handler.ghost_pokeDatas();

            uint len = pokeDatas.length;
            if (len != 0) {
                IScribe.PokeData memory lastPokeData = pokeDatas[len - 1];

                assertEq(lastPokeData.val, 0);
            }
        }
    }

    function invariant_peek_ReturnsTheLastPokedValue() public {
        (uint val, bool ok) = scribe.peek();
        if (ok) {
            IScribe.PokeData[] memory pokeDatas = handler.ghost_pokeDatas();

            uint len = pokeDatas.length;
            assertTrue(len != 0); // Otherwise peek should return false.

            IScribe.PokeData memory lastPokeData = pokeDatas[len - 1];
            assertEq(val, lastPokeData.val);
        }
    }

    /*//////////////////////////////////////////////////////////////
                       INVARIANTS: POKE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function invariant_poke_PokeTimestampsAreStrictlyMonotonicallyIncreasing()
        public
    {
        IScribe.PokeData[] memory pokeDatas = handler.ghost_pokeDatas();

        for (uint i = 1; i < pokeDatas.length; i++) {
            uint preAge = pokeDatas[i - 1].age;
            uint curAge = pokeDatas[i].age;

            assertTrue(preAge < curAge);
        }
    }

    function invariant_poke_SignersReachBar() public {
        // Return if bar updated since last poke.
        if (handler.ghost_barUpdated()) {
            return;
        }

        IScribe.SchnorrSignatureData[] memory schnorrSignatureDatas =
            handler.ghost_schnorrSignatureDatas();

        uint len = schnorrSignatureDatas.length;
        if (len != 0) {
            IScribe.SchnorrSignatureData memory last =
                schnorrSignatureDatas[len - 1];

            assertTrue(last.signers.length >= scribe.bar());
        }
    }

    function invariant_poke_SignersAreOrdered() public {
        IScribe.SchnorrSignatureData[] memory schnorrSignatureDatas =
            handler.ghost_schnorrSignatureDatas();

        uint len = schnorrSignatureDatas.length;
        if (len != 0) {
            IScribe.SchnorrSignatureData memory last =
                schnorrSignatureDatas[len - 1];

            for (uint i = 1; i < last.signers.length; i++) {
                uint160 pre = uint160(last.signers[i - 1]);
                uint160 cur = uint160(last.signers[i]);

                assertTrue(pre < cur);
            }
        }
    }

    function invariant_poke_SignersAreFeeds() public {
        // Return if bar updated since last poke.
        if (handler.ghost_FeedsDropped()) {
            return;
        }

        IScribe.SchnorrSignatureData[] memory schnorrSignatureDatas =
            handler.ghost_schnorrSignatureDatas();

        uint len = schnorrSignatureDatas.length;
        if (len != 0) {
            IScribe.SchnorrSignatureData memory last =
                schnorrSignatureDatas[len - 1];

            for (uint i; i < last.signers.length; i++) {
                assertTrue(scribe.feeds(last.signers[i]));
            }
        }
    }

    function invariant_poke_SchnorrSignatureValid() public {
        // @todo Implement once Schnorr signature verification enabled.
        console2.log("NOT IMPLEMENTED");
    }

    /*//////////////////////////////////////////////////////////////
                           INVARIANTS: FEEDS
    //////////////////////////////////////////////////////////////*/

    function invariant_feeds_OnlyContainsLiftedFeedAddresses() public {
        address[] memory feeds = scribe.feeds();

        for (uint i; i < feeds.length; i++) {
            assertTrue(scribe.feeds(feeds[i]));
        }
    }

    function invariant_feeds_ContainsAllLiftedFeedAddresses() public {
        address[] memory feedsTouched = handler.ghost_feedsTouched();
        address[] memory feeds = scribe.feeds();

        for (uint i; i < feedsTouched.length; i++) {
            // If touched feed is still feed...
            if (scribe.feeds(feedsTouched[i])) {
                // ...feeds list must contain it.
                for (uint j; j < feeds.length; j++) {
                    // Break inner loop if feed found.
                    if (feeds[j] == feedsTouched[i]) {
                        break;
                    }

                    // Fail if feeds list does not contain feed.
                    if (j == feeds.length - 1) {
                        assertTrue(false);
                    }
                }
            }
        }
    }

    function invariant_feeds_ZeroPointIsNotFeed() public {
        address zeroPointAddr = LibSecp256k1.Point(0, 0).toAddress();

        // Check via feeds(address)(bool)
        assertFalse(scribe.feeds(zeroPointAddr));

        // Check via feeds()(address[])
        address[] memory feeds = scribe.feeds();
        for (uint i; i < feeds.length; i++) {
            assertFalse(feeds[i] == zeroPointAddr);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS: BAR
    //////////////////////////////////////////////////////////////*/

    function invariant_bar_IsNeverZero() public {
        assertTrue(scribe.bar() != 0);
    }
}
