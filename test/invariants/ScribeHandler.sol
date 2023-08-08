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
    uint public scribe_lastPubKeysLength;

    uint internal nextPrivKey = 2;
    FeedSet internal feedSet;

    modifier cacheScribeState() {
        // forgefmt: disable-next-item
        _scribe_lastPokeData = ScribeInspectable(address(scribe)).inspectable_pokeData();
        // forgefmt: disable-next-item
        scribe_lastPubKeysLength = ScribeInspectable(address(scribe)).inspectable_pubKeys().length;
        _;
    }

    function init(address scribe_) public virtual {
        scribe = IScribe(scribe_);

        // Cache constants.
        WAT = scribe.wat();
        FEED_REGISTRATION_MESSAGE = scribe.feedRegistrationMessage();

        _ensureBarFeedsLifted();
    }

    function _ensureBarFeedsLifted() internal {
        uint bar = scribe.bar();
        (address[] memory feeds,) = scribe.feeds();

        if (feeds.length < bar) {
            // Lift feeds until bar is reached.
            uint missing = bar - feeds.length;
            LibFeed.Feed memory feed;
            for (uint i; i < missing; i++) {
                feed = LibFeed.newFeed(nextPrivKey++);

                // Lift feed and set its index.
                uint index = scribe.lift(
                    feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE)
                );
                feed.index = uint8(index);

                // Store feed in feedSet.
                feedSet.add(feed, true);
            }
        }
    }

    // -- Target Functions --

    function warp(uint seed) external {
        uint amount = bound(seed, 1, 1 hours);
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
        LibFeed.Feed[] memory feeds = feedSet.liftedFeeds(scribe.bar());

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
        LibFeed.Feed memory feed = LibFeed.newFeed(nextPrivKey++);

        // Lift feed and set its index.
        uint index =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        feed.index = uint8(index);

        // Store feed in feedSet.
        feedSet.add(feed, true);
    }

    function drop(uint seed) external cacheScribeState {
        // Get random feed from feedSet.
        // Note that feed may not be lifted.
        LibFeed.Feed memory feed = LibFeedSet.rand(feedSet, seed);

        // Receive index of feed. Index is zero if not lifted.
        (, uint index) = scribe.feeds(feed.pubKey.toAddress());

        // Drop feed.
        scribe.drop(index);

        // Mark feed as non-lifted in feedSet.
        feedSet.updateLifted(feed, false);
    }

    function setBar(uint barSeed) external cacheScribeState {
        uint8 newBar = uint8(bound(barSeed, 0, MAX_BAR));

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
        address[] memory addrs = new address[](feedSet.feeds.length);
        for (uint i; i < addrs.length; i++) {
            addrs[i] = feedSet.feeds[i].pubKey.toAddress();
        }
        return addrs;
    }

    // -- Helpers --

    function _randPokeDataVal(uint seed) internal view returns (uint128) {
        uint val = bound(seed, 0, type(uint128).max);
        return uint128(val);
    }

    function _randPokeDataAge(uint seed) internal view returns (uint32) {
        uint age = bound(seed, _scribe_lastPokeData.age + 1, block.timestamp);
        return uint32(age);
    }
}
