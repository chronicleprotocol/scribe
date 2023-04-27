pragma solidity ^0.8.16;

import {IScribe} from "src/IScribe.sol";

import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {ScribeOptimisticInspectable} from
    "../inspectable/ScribeOptimisticInspectable.sol";

import {ScribeHandler} from "./ScribeHandler.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";
import {LibFeed} from "script/libs/LibFeed.sol";

import {FeedSet, LibFeedSet} from "./FeedSet.sol";

contract ScribeOptimisticHandler is ScribeHandler {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];
    using LibFeedSet for FeedSet;

    uint public constant MAX_OP_CHALLENGE_PERIOD = 1 hours;

    IScribeOptimistic public opScribe;

    IScribe.SchnorrData private _ghost_lastSchnorrData;

    function init(address opScribe_) public override(ScribeHandler) {
        super.init(opScribe_);

        opScribe = IScribeOptimistic(opScribe_);
    }

    // -- Target Functions --

    function opPoke(uint valSeed, uint ageSeed, bool faulty)
        external
        cacheScribeState
    {
        _ensureBarFeedsLifted();

        // Get set of bar many feeds from feedSet.
        LibFeed.Feed[] memory feeds = feedSet.liftedFeeds(scribe.bar());

        // Create pokeData.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: _randPokeDataVal(valSeed),
            age: _randPokeDataAge(ageSeed)
        });

        bytes32 pokeMessage = scribe.constructPokeMessage(pokeData);
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(pokeMessage);

        // If requested, make schnorrData invalid.
        if (faulty) {
            schnorrData.commitment = address(0);
        }

        bytes32 opPokeMessage =
            opScribe.constructOpPokeMessage(pokeData, schnorrData);
        IScribe.ECDSAData memory ecdsaData = feeds[0].signECDSA(opPokeMessage);

        // Execute opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Store schnorrData.
        _ghost_lastSchnorrData = schnorrData;
    }

    function opChallenge() external {
        try opScribe.opChallenge(_ghost_lastSchnorrData) {} catch {}
    }

    function setOpChallengePeriod(uint16 opChallengePeriodSeed)
        external
        cacheScribeState
    {
        uint16 newOpChallengePeriod =
            uint16(bound(opChallengePeriodSeed, 0, MAX_OP_CHALLENGE_PERIOD));

        // Should revert if newOpChallengePeriod is 0.
        try opScribe.setOpChallengePeriod(newOpChallengePeriod) {} catch {}
    }
}
