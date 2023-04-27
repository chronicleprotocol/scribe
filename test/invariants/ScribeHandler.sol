pragma solidity ^0.8.16;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

contract ScribeHandler is CommonBase, StdUtils {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    struct State {
        IScribe.PokeData _pokeData;
        LibSecp256k1.Point[] _pubKeys;
        mapping(address => uint) _feeds;
        uint8 bar;
    }

    struct Transaction {
        bytes4 selector;
    }

    uint public constant MAX_BAR = 10;

    bytes32 public WAT;
    bytes32 public WAT_MESSAGE;

    IScribe public scribe;

    LibFeed.Feed[] internal _ghost_feeds;
    LibFeed.Feed[] internal _ghost_feedsTouched;
    mapping(uint => uint) internal _feedIndexesPerPrivKey;

    IScribe.PokeData[] internal _ghost_pokeDatas;
    IScribe.SchnorrData[] internal _ghost_schnorrSignatureDatas;
    uint32 public ghost_lastPokeTimestamp;
    bool public ghost_barUpdated;
    bool public ghost_FeedsLifted;
    bool public ghost_FeedsDropped;

    modifier noConfigsUpdated() {
        _;
        ghost_barUpdated = false;
        ghost_FeedsLifted = false;
        ghost_FeedsDropped = false;
    }

    //--------------------------------------------------------------------------
    // Initialization

    function init(address scribe_) external {
        scribe = IScribe(scribe_);

        // Cache constants.
        WAT = scribe.wat();
        WAT_MESSAGE = scribe.watMessage();

        // Create and whitelist 2 * MAX_BAR feeds.
        uint numberFeeds = 2 * MAX_BAR;
        LibFeed.Feed memory feed;
        for (uint i; i < numberFeeds; i++) {
            feed = LibFeed.newFeed({privKey: i + 2, index: uint8(i + 1)});

            _ghost_feeds.push(feed);
            _feedIndexesPerPrivKey[feed.privKey] = i;
            _ghost_feedsTouched.push(feed);

            scribe.lift(feed.pubKey, feed.signECDSA(WAT_MESSAGE));
        }
    }

    //--------------------------------------------------------------------------
    // Target Functions

    function warp(uint seed) external {
        uint amount = bound(seed, 0, 1 hours);
        vm.warp(block.timestamp + amount);
    }

    function poke(uint valSeed, uint ageSeed, uint numberSignersSeed)
        external
        noConfigsUpdated
    {
        // Create pokeData.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: _randPokeDataVal(valSeed),
            age: _randPokeDataAge(ageSeed)
        });

        // Make list of signers.
        // Note that the number of signers is random, but bounded to always
        // reach bar.
        uint numberSigners =
            bound(numberSignersSeed, scribe.bar(), _ghost_feeds.length);
        LibFeed.Feed[] memory signers = new LibFeed.Feed[](numberSigners);
        for (uint i; i < numberSigners; i++) {
            signers[i] = _ghost_feeds[i];
        }

        // Create schnorrSignatureData.
        IScribe.SchnorrData memory schnorrData;
        schnorrData = signers.signSchnorr(scribe.constructPokeMessage(pokeData));

        // Execute poke.
        scribe.poke(pokeData, schnorrData);

        // Store pokeData, schnorrSignatureData and current timestamp.
        _ghost_pokeDatas.push(pokeData);
        _ghost_schnorrSignatureDatas.push(schnorrData);
        ghost_lastPokeTimestamp = uint32(block.timestamp);
    }

    function pokeFaulty(
        uint valSeed,
        uint ageSeed,
        uint numberSignersSeed,
        bool includeNonFeedSigner,
        uint nonFeedSignerSeed,
        bool sortSigners
    ) external noConfigsUpdated {
        // Create pokeData.
        IScribe.PokeData memory pokeData = IScribe.PokeData({
            val: _randPokeDataVal(valSeed),
            age: _randPokeDataAge(ageSeed)
        });

        // Make list of signers.
        // Note that the number of signers is random, but bounded in a way that
        // gives a 50:50 chance of whether bar is reached.
        uint numberSigners = bound(numberSignersSeed, 0, 2 * scribe.bar());
        LibFeed.Feed[] memory signers = new LibFeed.Feed[](numberSigners);
        for (uint i; i < numberSigners; i++) {
            signers[i] = _ghost_feeds[i];
        }

        // @audit For some reason, the two seem to be codependent.
        //        See via: Uncomment corresponding checks individually.
        // Include non feed signer, if requested.
        if (includeNonFeedSigner) {
            uint index = bound(nonFeedSignerSeed, 0, numberSigners);
            // Point not on curve, so cannot be feed.
            signers[index] = LibFeed.Feed(1, LibSecp256k1.Point(1, 1), 0);
        }

        // @todo Make invalid, if requested.
        IScribe.SchnorrData memory schnorrData;
        schnorrData = signers.signSchnorr(scribe.constructPokeMessage(pokeData));

        // @todo If requested, randomize order of signers.
        if (!sortSigners) {
            //signers = LibHelpers.sortAddresses(signers);
        }

        // Execute poke.
        scribe.poke(pokeData, schnorrData);

        // Store pokeData, schnorrData and current timestamp.
        _ghost_pokeDatas.push(pokeData);
        _ghost_schnorrSignatureDatas.push(schnorrData);
        ghost_lastPokeTimestamp = uint32(block.timestamp);
    }

    function setBar(uint barSeed) external {
        uint8 newBar = uint8(bound(barSeed, 0, MAX_BAR));

        // Reverts if newBar is 0.
        scribe.setBar(newBar);

        // Set barUpdated flag to true.
        ghost_barUpdated = true;
    }

    function lift(uint privKey) external {
        // Return if feed exists already.
        if (_feedIndexesPerPrivKey[privKey] != 0) {
            return;
        }

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        _ghost_feeds.push(feed);
        _feedIndexesPerPrivKey[privKey] = _ghost_feeds.length - 1;
        _ghost_feedsTouched.push(feed);
        scribe.lift(feed.pubKey, feed.signECDSA(WAT_MESSAGE));

        // Set feedsLifted flag to true.
        ghost_FeedsLifted = true;
    }

    function drop(uint feedSeed) external {
        uint feedIndex = bound(feedSeed, 0, _ghost_feeds.length);

        scribe.drop(_ghost_feeds[feedIndex].index);

        // Remove feed from internal list of feeds.
        delete _feedIndexesPerPrivKey[_ghost_feeds[feedIndex].privKey];
        delete _ghost_feeds[feedIndex];

        // Set feedsDropped flag to true.
        ghost_FeedsDropped = true;
    }

    //--------------------------------------------------------------------------
    // Ghost View Functions

    function ghost_feeds() external view returns (address[] memory) {
        address[] memory feeds = new address[](_ghost_feeds.length);

        for (uint i; i < feeds.length; i++) {
            feeds[i] = _ghost_feeds[i].pubKey.toAddress();
        }

        return feeds;
    }

    function ghost_feedsTouched() external view returns (address[] memory) {
        address[] memory feedsTouched =
            new address[](_ghost_feedsTouched.length);

        for (uint i; i < feedsTouched.length; i++) {
            feedsTouched[i] = _ghost_feedsTouched[i].pubKey.toAddress();
        }

        return feedsTouched;
    }

    function ghost_pokeDatas()
        external
        view
        returns (IScribe.PokeData[] memory)
    {
        return _ghost_pokeDatas;
    }

    function ghost_schnorrSignatureDatas()
        external
        view
        returns (IScribe.SchnorrData[] memory)
    {
        return _ghost_schnorrSignatureDatas;
    }

    //--------------------------------------------------------------------------
    // Private Helpers

    function _randPokeDataVal(uint seed) private view returns (uint128) {
        return uint128(bound(seed, 0, type(uint128).max));
    }

    function _randPokeDataAge(uint seed) private view returns (uint32) {
        uint32 last = ghost_lastPokeTimestamp;

        // Note that an age of last reverts.
        return uint32(bound(seed, last, block.timestamp));
    }
}
