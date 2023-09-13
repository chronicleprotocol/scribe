// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";
import {LibOracleSuite} from "script/libs/LibOracleSuite.sol";

abstract contract IScribeTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    IScribe private scribe;

    bytes32 internal WAT;
    bytes32 internal FEED_REGISTRATION_MESSAGE;

    mapping(address => bool) internal addressFilter;

    // Events copied from IScribe.
    event Poked(address indexed caller, uint128 val, uint32 age);
    event FeedLifted(
        address indexed caller, address indexed feed, uint8 indexed feedId
    );
    event FeedDropped(
        address indexed caller, address indexed feed, uint8 indexed feedId
    );
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    function setUp(address scribe_) internal virtual {
        scribe = IScribe(scribe_);

        // Cache constants.
        WAT = scribe.wat();
        FEED_REGISTRATION_MESSAGE = scribe.feedRegistrationMessage();

        // Toll address(this).
        IToll(address(scribe)).kiss(address(this));
    }

    /*
    // @todo Make script to generate feeds.
    // @todo Check whether ffi reading .json file would be faster.
    function _setUpFeeds() internal {
        // Note to not start with privKey=1. This is because the sum of public
        // keys would evaluate to:
        //   pubKeyOf(1) + pubKeyOf(2) + pubKeyOf(3) + ...
        // = pubKeyOf(3)               + pubKeyOf(3) + ...
        // Note that pubKeyOf(3) would be doubled. Doubling is not supported by
        // LibSecp256k1 as this would indicate a double-signing attack.
        uint privKey = 2;

        uint bloom;
        while (true) {
            LibSecp256k1.Point memory pubKey = privKey.derivePublicKey();
            uint8 id = uint8(uint(uint160(pubKey.toAddress())) >> 152);

            if (bloom & (1 << uint(id)) == 0) {
                bloom |= 1 << uint(id);

                feeds[uint(id)] = LibFeed.newFeed({privKey: privKey});
            }

            if (bloom == type(uint).max) {
                break;
            }

            privKey++;
        }
    }
    */

    function _liftFeeds(uint8 numberFeeds)
        internal
        returns (LibFeed.Feed[] memory)
    {
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](uint(numberFeeds));

        // Note to not start with privKey=1. This is because the sum of public
        // keys would evaluate to:
        //   pubKeyOf(1) + pubKeyOf(2) + pubKeyOf(3) + ...
        // = pubKeyOf(3)               + pubKeyOf(3) + ...
        // Note that pubKeyOf(3) would be doubled. Doubling is not supported by
        // LibSecp256k1 as this would indicate a double-signing attack.
        uint privKey = 2;
        uint bloom;
        uint ctr;
        while (true) {
            LibFeed.Feed memory feed = LibFeed.newFeed({privKey: privKey});
            uint8 id = uint8(uint(uint160(feed.pubKey.toAddress())) >> 152);

            // Check whether feed with id already created, if not create and
            // lift.
            if (bloom & (1 << uint(id)) == 0) {
                bloom |= 1 << uint(id);

                feeds[ctr++] = feed;
                scribe.lift(
                    feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE)
                );
            }

            // Break if feed for each id created and lifted.
            if (ctr == uint(numberFeeds)) {
                break;
            }

            privKey++;
        }

        return feeds;
    }

    function _checkReadFunctions(uint wantVal, uint wantAge) internal {
        bool ok;
        uint gotVal;
        uint gotAge;

        assertEq(scribe.read(), wantVal);

        (ok, gotVal) = scribe.tryRead();
        assertEq(gotVal, wantVal);
        assertTrue(ok);

        (gotVal, gotAge) = scribe.readWithAge();
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);

        (ok, gotVal, gotAge) = scribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);

        (gotVal, ok) = scribe.peek();
        assertEq(gotVal, wantVal);
        assertTrue(ok);

        (gotVal, ok) = scribe.peep();
        assertEq(gotVal, wantVal);
        assertTrue(ok);

        (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = scribe.latestRoundData();
        assertEq(uint(roundId), 1);
        assertEq(uint(answer), wantVal);
        assertEq(startedAt, 0);
        assertEq(updatedAt, wantAge);
        assertEq(uint(answeredInRound), 1);
    }

    // -- Test: Deployment --

    function test_Deployment() public virtual {
        // Address given as constructor argument is auth'ed.
        assertTrue(IAuth(address(scribe)).authed(address(this)));

        // Wat is set.
        assertEq(scribe.wat(), "ETH/USD");

        // Bar set to 2.
        assertEq(scribe.bar(), 2);

        // Set of feeds is empty.
        (address[] memory feeds_, uint[] memory feedsIndexes) = scribe.feeds();
        assertEq(feeds_.length, 0);
        assertEq(feedsIndexes.length, 0);

        // read()(uint) fails.
        try scribe.read() returns (uint) {
            assertTrue(false);
        } catch {}

        bool ok;
        uint val;
        uint age;

        // tryRead()(bool,uint) returns false.
        (ok, val) = scribe.tryRead();
        assertFalse(ok);
        assertEq(val, 0);

        // readWithAge()(uint,uint) fails.
        try scribe.readWithAge() returns (uint, uint) {
            assertTrue(false);
        } catch {}

        // tryReadWithAge()(bool,uint,uint) returns false.
        (ok, val, age) = scribe.tryReadWithAge();
        assertFalse(ok);
        assertEq(val, 0);
        assertEq(age, 0);

        // peek()(uint,bool) returns false.
        // Note that peek()(uint,bool) is deprecated.
        (val, ok) = scribe.peek();
        assertEq(val, 0);
        assertFalse(ok);

        // peep()(uint,bool) returns false.
        // Note that peep()(uint,bool) is deprecated.
        (val, ok) = scribe.peep();
        assertEq(val, 0);
        assertFalse(ok);

        // latestRound()(uint80,int,uint,uint,uint80) returns zero.
        uint80 roundId;
        int answer;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            scribe.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    // -- Test: Schnorr Verification --

    /*

    function testFuzz_isAcceptableSchnorrSignatureNow(uint barSeed) public {
        // Let bar ∊ [1, scribe.maxFeeds()].
        uint8 bar = uint8(_bound(barSeed, 1, scribe.maxFeeds()));

        scribe.setBar(bar);

        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        bytes32 message = keccak256("scribe");

        bool ok = scribe.isAcceptableSchnorrSignatureNow(
            message, feeds.signSchnorr(message)
        );
        assertTrue(ok);
    }

    function testFuzz_isAcceptableSchnorrSignatureNow_FailsIf_BarNotReached(
        uint barSeed,
        uint numberSignersSeed
    ) public {
        // Let bar ∊ [2, scribe.maxFeeds()].
        uint8 bar = uint8(_bound(barSeed, 2, scribe.maxFeeds()));

        // Let numberSigners ∊ [1, bar).
        uint numberSigners = _bound(numberSignersSeed, 1, uint(bar) - 1);

        scribe.setBar(bar);
        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        assembly ("memory-safe") {
            // Set length of feeds list to numberSigners.
            mstore(feeds, numberSigners)
        }

        bytes32 message = keccak256("scribe");

        bool ok = scribe.isAcceptableSchnorrSignatureNow(
            message, feeds.signSchnorr(message)
        );
        assertFalse(ok);
    }

    function testFuzz_isAcceptableSchnorrSignatureNow_FailsIf_DoubleSigningAttempted(
        uint barSeed,
        uint doubleSignerIndexSeed
    ) public {
        // Let bar ∊ [2, scribe.maxFeeds()].
        uint8 bar = uint8(_bound(barSeed, 2, scribe.maxFeeds()));

        // Let doubleSignerIndex ∊ [1, bar).
        uint doubleSignerIndex = _bound(doubleSignerIndexSeed, 1, uint(bar) - 1);

        scribe.setBar(bar);
        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        // Let random feed double sign.
        feeds[0] = feeds[doubleSignerIndex];

        bytes32 message = keccak256("scribe");

        bool ok = scribe.isAcceptableSchnorrSignatureNow(
            message, feeds.signSchnorr(message)
        );
        assertFalse(ok);
    }

    function testFuzz_isAcceptableSchnorrSignatureNow_FailsIf_SignerNotFeed(
        uint privKeySeed
    ) public {
        // Let privKey ∊ [1, Q).
        uint privKey = _bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Note to not lift feed.
        LibFeed.Feed memory feed = LibFeed.newFeed({privKey: privKey});

        scribe.setBar(uint8(1));

        bytes32 message = keccak256("scribe");

        bool ok = scribe.isAcceptableSchnorrSignatureNow(
            message, feed.signSchnorr(message)
        );
        assertFalse(ok);
    }

    function testFuzz_isAcceptableSchnorrSignatureNow_FailsIf_SignatureInvalid(
        uint barSeed
    ) public {
        // Let bar ∊ [1, scribe.maxFeeds()].
        uint8 bar = uint8(_bound(barSeed, 1, scribe.maxFeeds()));

        scribe.setBar(bar);
        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        bytes32 message = keccak256("scribe");

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(message);

        // Mutate schnorrData's signature.
        unchecked {
            schnorrData.signature = bytes32(uint(schnorrData.signature) + 1);
        }

        bool ok = scribe.isAcceptableSchnorrSignatureNow(message, schnorrData);
        assertFalse(ok);
    }

    // -- Test: Poke --

    function testFuzz_poke(IScribe.PokeData[] memory pokeDatas) public {
        vm.assume(pokeDatas.length < 50);

        // @todo MUST have random bar!
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        uint32 lastPokeTimestamp = 0;
        IScribe.SchnorrData memory schnorrData;
        for (uint i; i < pokeDatas.length; i++) {
            pokeDatas[i].val =
                uint128(bound(pokeDatas[i].val, 1, type(uint128).max));
            pokeDatas[i].age = uint32(
                bound(pokeDatas[i].age, lastPokeTimestamp + 1, block.timestamp)
            );

            schnorrData =
                feeds.signSchnorr(scribe.constructPokeMessage(pokeDatas[i]));

            vm.expectEmit();
            emit Poked(address(this), pokeDatas[i].val, pokeDatas[i].age);

            scribe.poke(pokeDatas[i], schnorrData);

            _checkReadFunctions(pokeDatas[i].val, block.timestamp);

            lastPokeTimestamp = uint32(block.timestamp);
            vm.warp(block.timestamp + 10 minutes);
        }
    }

    function test_poke_Initial_FailsIf_AgeIsZero() public {
        // @todo Use random bar!
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 0;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.StaleMessage.selector, 0, 0)
        );
        scribe.poke(pokeData, schnorrData);
    }

    function testFuzz_poke_FailsIf_AgeIsStale(IScribe.PokeData memory pokeData)
        public
    {
        // @todo Use random bar!
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        vm.assume(pokeData.val != 0);
        // Let pokeData's age ∊ [1, block.timestamp].
        pokeData.age = uint32(bound(pokeData.age, 1, block.timestamp));

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        // Poke once.
        scribe.poke(pokeData, schnorrData);

        // Last poke's age is set to block.timestamp.
        uint currentAge = uint32(block.timestamp);

        // Set pokeData's age ∊ [0, block.timestamp].
        pokeData.age = uint32(bound(pokeData.age, 0, block.timestamp));

        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        // Poke again, expect message to be stable.
        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.StaleMessage.selector, pokeData.age, currentAge
            )
        );
        scribe.poke(pokeData, schnorrData);
    }

    function testFuzz_poke_FailsIf_AgeIsInTheFuture(
        IScribe.PokeData memory pokeData
    ) public {
        // @todo Use random bar!
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        vm.assume(pokeData.val != 0);
        // Let pokeData's age ∊ [block.timestamp+1, type(uint32).max].
        pokeData.age =
            uint32(bound(pokeData.age, block.timestamp + 1, type(uint32).max));

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.FutureMessage.selector,
                pokeData.age,
                uint32(block.timestamp)
            )
        );
        scribe.poke(pokeData, schnorrData);
    }

    function testFuzz_poke_FailsIf_SignatureInvalid(
        IScribe.PokeData memory pokeData
    ) public {
        // @todo Use random bar!
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        // @todo Use bound.
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0 && pokeData.age <= uint32(block.timestamp));

        // Create schnorrData signing different message.
        bytes32 message = keccak256("scribe");
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(message);

        vm.expectRevert(IScribe.SchnorrSignatureInvalid.selector);
        scribe.poke(pokeData, schnorrData);
    }

    */

    // -- Test: constructPokeMessage --

    // @todo Disabled during dev.
    /*
    function testFuzzDifferentialOracleSuite_constructPokeMessage(
        IScribe.PokeData memory pokeData
    ) public {
        bytes32 want = scribe.constructPokeMessage(pokeData);
        bytes32 got = LibOracleSuite.constructPokeMessage(
            scribe.wat(), pokeData.val, pokeData.age
        );
        assertEq(want, got);
    }
    */

    // -- Test: Auth Protected Functions --

    function testFuzz_lift_Single(uint privKey) public {
        // Let privKey ∊ [1, Q).
        privKey = _bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        vm.expectEmit();
        emit FeedLifted(address(this), feed.pubKey.toAddress(), feed.id);

        uint index =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        assertEq(index, feed.id);

        // Check via feeds(address)(bool,uint).
        bool ok;
        (ok, index) = scribe.feeds(feed.pubKey.toAddress());
        assertTrue(ok);
        assertEq(index, feed.id);

        // Check via feeds(uint)(bool,address).
        address feedAddr;
        (ok, feedAddr) = scribe.feeds(feed.id);
        assertTrue(ok);
        assertEq(feedAddr, feed.pubKey.toAddress());

        // Check via feeds()(address[],uint[]).
        address[] memory feeds_;
        uint[] memory indexes;
        (feeds_, indexes) = scribe.feeds();
        assertEq(feeds_.length, indexes.length);
        assertEq(feeds_.length, 1);
        assertEq(feeds_[0], feed.pubKey.toAddress());
        assertEq(indexes[0], feed.id);
    }

    function test_lift_Single_FailsIf_ECDSADataInvalid() public {
        uint privKeySigner = 1;
        uint privKeyFeed = 2;

        vm.expectRevert();
        scribe.lift(
            LibFeed.newFeed(privKeyFeed).pubKey,
            LibFeed.newFeed(privKeySigner).signECDSA(FEED_REGISTRATION_MESSAGE)
        );
    }

    // @todo Not needed anymore. Every feed's index is naturally bound by 256.
    /*
    function test_lift_Single_FailsIf_MaxFeedsReached() public {
        uint maxFeeds = scribe.maxFeeds();

        // Lift maxFeeds feeds.
        LibFeed.Feed memory feed;
        for (uint i; i < maxFeeds; i++) {
            feed = LibFeed.newFeed(i + 1);
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        }

        feed = LibFeed.newFeed(maxFeeds + 1);
        vm.expectRevert();
        scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
    }
    */

    /*
    function testFuzz_lift_Multiple(uint[] memory privKeys) public {
        //LibFeed.Feed[] memory feeds =

        // Let each privKey ∊ [1, Q).
        for (uint i; i < privKeys.length; i++) {
            privKeys[i] = bound(privKeys[i], 1, LibSecp256k1.Q() - 1);
        }

        // Make feeds.
        LibFeed.Feed[] memory feeds_ = new LibFeed.Feed[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            feeds_[i] = LibFeed.newFeed(privKeys[i]);
        }

        // Make list of public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            pubKeys[i] = feeds_[i].pubKey;
        }

        // Make signatures.
        IScribe.ECDSAData[] memory ecdsaDatas =
            new IScribe.ECDSAData[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            ecdsaDatas[i] = feeds_[i].signECDSA(FEED_REGISTRATION_MESSAGE);
        }

        for (uint i; i < feeds_.length; i++) {
            // Don't expect event for duplicates.
            if (!addressFilter[feeds_[i].pubKey.toAddress()]) {
                vm.expectEmit();
                emit FeedLifted(
                    address(this), feeds_[i].pubKey.toAddress(), feeds_[i].id
                );
            }
            addressFilter[feeds_[i].pubKey.toAddress()] = true;
        }

        uint[] memory indexes = scribe.lift(pubKeys, ecdsaDatas);
        assertEq(indexes.length, pubKeys.length);
        for (uint i; i < indexes.length; i++) {
            assertTrue(indexes[i] != 0 && indexes[i] < pubKeys.length + 1);
        }

        // Check via feeds(address)(bool,uint) and feeds(uint)(bool,address).
        bool ok;
        uint8 feedId;
        address feed;
        for (uint i; i < pubKeys.length; i++) {
            (ok, feedId) = scribe.feeds(pubKeys[i].toAddress());
            assertTrue(ok);

            (ok, feedAddr) = scribe.feeds(feedId);
            assertTrue(ok);
            assertEq(pubKeys[i].toAddress(), feed);
        }

        // Check via feeds()(address[],uint[]).
        address[] memory addrs;
        (feeds, feedIds) = scribe.feeds();
        for (uint i; i < pubKeys.length; i++) {
            for (uint j; j < feeds.length; j++) {
                // Break inner loop if pubKey's address found in list of feeds.
                if (pubKeys[i].toAddress() == feeds[j]) {
                    break;
                }

                // Fail if pubKey's address not found in list of feeds.
                if (j == feeds.length - 1) {
                    assertTrue(false);
                }
            }
        }
    }
    */

    function test_lift_Multiple_FailsIf_ECDSADataInvalid() public {
        uint privKeySigner = 1;
        uint privKeyFeed = 2;

        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](2);
        feeds[0] = LibFeed.newFeed(privKeySigner);
        feeds[1] = LibFeed.newFeed(privKeyFeed);

        IScribe.ECDSAData[] memory ecdsaDatas = new IScribe.ECDSAData[](2);
        ecdsaDatas[0] = feeds[0].signECDSA(FEED_REGISTRATION_MESSAGE);
        ecdsaDatas[1] = ecdsaDatas[0];

        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](2);
        pubKeys[0] = feeds[0].pubKey;
        pubKeys[1] = feeds[1].pubKey;

        vm.expectRevert();
        scribe.lift(pubKeys, ecdsaDatas);
    }

    // @todo Not needed anymore. Every feed's index is naturally bound by 256.
    /*
    function test_lift_Multiple_FailsIf_MaxFeedsReached() public {
        uint maxFeeds = scribe.maxFeeds();

        // Make feeds.
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](maxFeeds + 1);
        for (uint i; i < maxFeeds + 1; i++) {
            feeds[i] = LibFeed.newFeed(i + 1);
        }

        // Make list of public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](maxFeeds + 1);
        for (uint i; i < maxFeeds + 1; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Make signatures.
        IScribe.ECDSAData[] memory ecdsaDatas =
            new IScribe.ECDSAData[](maxFeeds + 1);
        for (uint i; i < maxFeeds + 1; i++) {
            ecdsaDatas[i] = feeds[i].signECDSA(FEED_REGISTRATION_MESSAGE);
        }

        vm.expectRevert();
        scribe.lift(pubKeys, ecdsaDatas);
    }
    */

    function testFuzz_lift_Multiple_FailsIf_ArrayLengthMismatch(
        LibSecp256k1.Point[] memory pubKeys,
        IScribe.ECDSAData[] memory ecdsaDatas
    ) public {
        vm.assume(pubKeys.length != ecdsaDatas.length);

        vm.expectRevert();
        scribe.lift(pubKeys, ecdsaDatas);
    }

    /*
    function testFuzz_drop_Single(uint privKey) public {
        // Let privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        uint8 feedId =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));

        vm.expectEmit();
        emit FeedDropped(address(this), feed.pubKey.toAddress(), feedId);

        scribe.drop(feedId);

        // Check via feeds(address)(bool).
        bool ok;
        (ok, index) = scribe.feeds(feed.pubKey.toAddress());
        assertFalse(ok);
        //assertEq(index, 0);

        // Check via feeds(uint)(bool,address).
        address feedAddr;
        (ok, feedAddr) = scribe.feeds(index);
        assertFalse(ok);
        assertEq(feedAddr, address(0));

        // Check via feeds()(address[],uint[]).
        address[] memory feeds_;
        uint[] memory indexes;
        (feeds_, indexes) = scribe.feeds();
        assertEq(feeds_.length, indexes.length);
        assertEq(feeds_.length, 0);
    }
    */

    /*
    function testFuzz_drop_Multiple(uint[] memory privKeys) public {
        // Let each privKey ∊ [1, Q).
        for (uint i; i < privKeys.length; i++) {
            privKeys[i] = _bound(privKeys[i], 1, LibSecp256k1.Q() - 1);
        }

        // Make feeds.
        LibFeed.Feed[] memory feeds_ = new LibFeed.Feed[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            feeds_[i] = LibFeed.newFeed(privKeys[i]);
        }

        // Make list of public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            pubKeys[i] = feeds_[i].pubKey;
        }

        // Make signatures.
        IScribe.ECDSAData[] memory ecdsaDatas =
            new IScribe.ECDSAData[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            ecdsaDatas[i] = feeds_[i].signECDSA(FEED_REGISTRATION_MESSAGE);
        }

        // Lift feeds.
        uint[] memory indexes = scribe.lift(pubKeys, ecdsaDatas);

        // Expect events.
        uint indexCtr = 1;
        for (uint i; i < pubKeys.length; i++) {
            // Don't expect event for duplicates.
            if (!addressFilter[pubKeys[i].toAddress()]) {
                vm.expectEmit();
                emit FeedDropped(
                    address(this), pubKeys[i].toAddress(), indexCtr++
                );
            }

            addressFilter[pubKeys[i].toAddress()] = true;
        }

        // Drop feeds.
        scribe.drop(indexes);

        // Check via feeds(address)(bool,uint).
        bool ok;
        uint index;
        for (uint i; i < pubKeys.length; i++) {
            (ok, index) = scribe.feeds(pubKeys[i].toAddress());
            assertFalse(ok);
            assertEq(index, 0);
        }

        // Check via feeds()(address[],uint[]).
        address[] memory feedAddresses;
        uint[] memory feedIndexes;
        (feedAddresses, feedIndexes) = scribe.feeds();
        assertEq(feedAddresses.length, feedIndexes.length);
        assertEq(feedAddresses.length, 0);
    }

    function test_drop_IsIdempotent(uint privKeySeed) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(1);
        scribe.drop(feeds[0].index);

        // Second call is idempotent.
        scribe.drop(feeds[0].index);
    }

    // @todo Unnecessary when switched to uint8 for id.
    function testFuzz_drop_Single_FailsIf_IndexOutOfBounds(uint index) public {
        vm.assume(index > scribe.maxFeeds());

        vm.expectRevert();
        scribe.drop(index);
    }

    // @todo Unnecessary when switched to uint8 for id.
    function testFuzz_drop_Multiple_FailsIf_IndexOutOfBounds(
        uint[] memory indexes
    ) public {
        vm.assume(indexes.length != 0);
        indexes[indexes.length - 1] = type(uint8).max;

        vm.expectRevert();
        scribe.drop(indexes);
    }

    function testFuzz_liftDropLift(uint privKey) public {
        // Let privKey ∊ [1, Q).
        privKey = _bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        bool ok;
        uint index;

        // @todo Test whether index is correctly computed (1 byte).
        index =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        //assertEq(index, 1);
        (ok, index) = scribe.feeds(feed.pubKey.toAddress());
        assertTrue(ok);
        //assertEq(index, 1);

        scribe.drop(index);
        (ok, index) = scribe.feeds(feed.pubKey.toAddress());
        assertFalse(ok);
        //assertEq(index, 0);

        // @todo Comment off. Whole test needs refactoring.
        // Note that lifting same feed again leads to an increased index
        // nevertheless.
        index =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        //assertEq(index, 2);
        (ok, index) = scribe.feeds(feed.pubKey.toAddress());
        assertTrue(ok);
        //assertEq(index, 2);

        address[] memory feedAddrs;
        uint[] memory feedIndexes;
        (feedAddrs, feedIndexes) = scribe.feeds();
        assertEq(feedAddrs.length, 1);
        assertEq(feedIndexes.length, 1);
        assertEq(feedAddrs[0], feed.pubKey.toAddress());
        //assertEq(feedIndexes[0], 2);
    }

    function testFuzz_setBar(uint8 bar) public {
        vm.assume(bar != 0);

        // Only expect event if bar actually changes.
        if (bar != scribe.bar()) {
            vm.expectEmit();
            emit BarUpdated(address(this), scribe.bar(), bar);
        }

        scribe.setBar(bar);

        assertEq(scribe.bar(), bar);
    }

    function test_setBar_FailsIf_BarIsZero() public {
        vm.expectRevert();
        scribe.setBar(0);
    }

    function test_toll_kiss_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        IToll(address(scribe)).kiss(address(0));
    }

    function test_toll_diss_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        IToll(address(scribe)).diss(address(0));
    }

    function test_lift_Single_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.lift(LibSecp256k1.ZERO_POINT(), IScribe.ECDSAData(0, 0, 0));
    }

    function test_lift_Multiple_IsAuthProtected() public {
        LibSecp256k1.Point[] memory pubKeys;
        IScribe.ECDSAData[] memory ecdsaDatas;

        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.lift(pubKeys, ecdsaDatas);
    }

    function test_drop_Single_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.drop(0);
    }

    function test_drop_Multiple_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.drop(new uint[](1));
    }

    function test_setBar_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.setBar(0);
    }

    // -- Test: Toll Protected Functions --

    // - IChronicle Functions

    function test_read_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.read();
    }

    function test_tryRead_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.tryRead();
    }

    function test_readWithAge_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.readWithAge();
    }

    function test_tryReadWithAge_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.tryReadWithAge();
    }

    // - MakerDAO Compatibility

    function test_peek_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.peek();
    }

    function test_peep_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.peep();
    }

    // - Chainlink Compatibility

    function test_latestRoundData_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.latestRoundData();
    }
    */
}
