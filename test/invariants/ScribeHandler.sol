// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

import {IScribe} from "src/IScribe.sol";
import {ScribeInspectable} from "../inspectable/ScribeInspectable.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

import {FeedSet, LibFeedSet} from "./FeedSet.sol";

contract ScribeHandler is CommonBase, StdUtils {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];
    using LibFeedSet for FeedSet;

    uint public constant MAX_BAR = 10;

    bytes32 public WAT;
    bytes32 public FEED_REGISTRATION_MESSAGE;

    IScribe public scribe;

    IScribe.PokeData internal _scribe_lastPokeData;

    uint internal _nextPrivKey = 2;
    FeedSet internal _feedSet;

    modifier cacheScribeState() {
        // forgefmt: disable-next-item
        _scribe_lastPokeData = ScribeInspectable(address(scribe)).inspectable_pokeData();
        _;
    }

    function init(address scribe_) public virtual {
        scribe = IScribe(scribe_);

        // Cache constants.
        WAT = scribe.wat();
        FEED_REGISTRATION_MESSAGE = scribe.feedRegistrationMessage();
    }

    function _ensureBarFeedsLifted() internal {
        uint bar = scribe.bar();
        (address[] memory feeds,) = scribe.feeds();

        if (feeds.length < bar) {
            // Lift feeds until bar is reached.
            uint missing = bar - feeds.length;
            LibFeed.Feed memory feed;
            while (missing != 0) {
                feed = LibFeed.newFeed(_nextPrivKey++);

                // Continue if feed's id already lifted.
                (bool isFeed,) = scribe.feeds(feed.id);
                if (isFeed) continue;

                // Otherwise lift feed and add to feedSet.
                scribe.lift(
                    feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE)
                );
                _feedSet.add({feed: feed, lifted: true});

                missing--;
            }
        }
    }

    // -- Target Functions --

    function warp(uint seed) external cacheScribeState {
        uint amount = _bound(seed, 1, 1 hours);
        vm.warp(block.timestamp + amount);
    }

    function poke(uint valSeed, uint ageSeed) external cacheScribeState {
        _ensureBarFeedsLifted();

        // Wait some time if executed in same timestamp as last poke.
        if (_scribe_lastPokeData.age + 1 >= block.timestamp) {
            vm.warp(
                block.timestamp
                    + ((_scribe_lastPokeData.age + 1) - block.timestamp) + 1
            );
        }

        // Get set of bar many feeds from feedSet.
        LibFeed.Feed[] memory feeds = _feedSet.liftedFeeds(scribe.bar());

        // Create pokeData.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: _randPokeDataVal(valSeed),
            age: _randPokeDataAge(ageSeed)
        });

        bytes32 pokeMessage = scribe.constructPokeMessage(pokeData);
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(pokeMessage);

        // Note to not poke if schnorr signature is valid, but not acceptable.
        bool ok =
            scribe.isAcceptableSchnorrSignatureNow(pokeMessage, schnorrData);
        if (ok) {
            // Execute poke.
            scribe.poke(pokeData, feeds.signSchnorr(pokeMessage));
        } else {
            console2.log(
                StdStyle.yellow(
                    "ScribeHandler::poke: Skipping because Schnorr cannot be verified"
                )
            );
        }
    }

    function lift() external cacheScribeState {
        // Create new feed.
        LibFeed.Feed memory feed = LibFeed.newFeed(_nextPrivKey++);

        // Return if feed's id already lifted.
        (bool isFeed,) = scribe.feeds(feed.id);
        if (isFeed) return;

        // Lift feed and add to feedSet.
        scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        _feedSet.add({feed: feed, lifted: true});
    }

    function drop(uint seed) external cacheScribeState {
        if (_feedSet.count() == 0) return;

        // Get random feed from feedSet.
        // Note that feed may not be lifted.
        LibFeed.Feed memory feed = _feedSet.rand(seed);

        // Drop feed and mark as non-lifted in feedSet.
        scribe.drop(feed.id);
        _feedSet.updateLifted({feed: feed, lifted: false});
    }

    function setBar(uint barSeed) external cacheScribeState {
        uint8 newBar = uint8(_bound(barSeed, 0, MAX_BAR));

        // Should revert if newBar is 0.
        try scribe.setBar(newBar) {} catch {}
    }

    // -- Ghost View Functions --

    function scribe_lastPokeData()
        external
        view
        returns (IScribe.PokeData memory)
    {
        return _scribe_lastPokeData;
    }

    function ghost_feedAddresses() external view returns (address[] memory) {
        address[] memory addrs = new address[](_feedSet.feeds.length);
        for (uint i; i < addrs.length; i++) {
            addrs[i] = _feedSet.feeds[i].pubKey.toAddress();
        }
        return addrs;
    }

    // -- Helpers --

    function _randPokeDataVal(uint seed) internal pure returns (uint128) {
        uint val = _bound(seed, 0, type(uint128).max);
        return uint128(val);
    }

    function _randPokeDataAge(uint seed) internal view returns (uint32) {
        uint age = _bound(seed, _scribe_lastPokeData.age + 1, block.timestamp);
        return uint32(age);
    }
}
