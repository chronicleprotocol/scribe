// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

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

    // Events copied from IScribe.
    event Poked(address indexed caller, uint128 val, uint32 age);
    event FeedLifted(address indexed caller, address indexed feed);
    event FeedDropped(address indexed caller, address indexed feed);
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    function setUp(address scribe_) internal virtual {
        scribe = IScribe(scribe_);

        // Cache constants.
        WAT = scribe.wat();
        FEED_REGISTRATION_MESSAGE = scribe.feedRegistrationMessage();

        // Toll address(this).
        IToll(address(scribe)).kiss(address(this));
    }

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
        while (ctr != numberFeeds) {
            LibFeed.Feed memory feed = LibFeed.newFeed({privKey: privKey});

            // Check whether feed with id already created, if not create and
            // lift.
            if (bloom & (1 << feed.id) == 0) {
                bloom |= 1 << feed.id;

                feeds[ctr++] = feed;
                scribe.lift(
                    feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE)
                );
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

        answer = scribe.latestAnswer();
        assertEq(uint(answer), wantVal);
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
        address[] memory feeds = scribe.feeds();
        assertEq(feeds.length, 0);

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

        // latestAnswer()(int) returns zero.
        assertEq(scribe.latestAnswer(), int(0));
    }

    // -- Test: Schnorr Verification --

    function testFuzz_isAcceptableSchnorrSignatureNow(uint barSeed) public {
        // Let bar ∊ [1, 256).
        uint8 bar = uint8(_bound(barSeed, 1, 256 - 1));
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
        uint numberFeedsSeed
    ) public {
        // Let bar ∊ [2, 256).
        uint8 bar = uint8(_bound(barSeed, 2, 256 - 1));
        scribe.setBar(bar);
        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        // Let numberFeeds ∊ [1, bar).
        uint numberFeeds = _bound(numberFeedsSeed, 1, uint(bar) - 1);

        assembly ("memory-safe") {
            // Set length of feeds list to numberFeeds.
            mstore(feeds, numberFeeds)
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
        // Let bar ∊ [2, 256).
        uint8 bar = uint8(_bound(barSeed, 2, 256 - 1));
        scribe.setBar(bar);
        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        // Let doubleSignerIndex ∊ [1, bar).
        uint doubleSignerIndex = _bound(doubleSignerIndexSeed, 1, uint(bar) - 1);

        // Let random feed double sign.
        feeds[0] = feeds[doubleSignerIndex];

        bytes32 message = keccak256("scribe");

        bool ok = scribe.isAcceptableSchnorrSignatureNow(
            message, feeds.signSchnorr(message)
        );
        assertFalse(ok);
    }

    function testFuzz_isAcceptableSchnorrSignatureNow_FailsIf_InvalidFeedId(
        uint barSeed,
        uint privKeySeed,
        uint indexSeed
    ) public {
        // Let bar ∊ [2, 256).
        uint8 bar = uint8(_bound(barSeed, 2, 256 - 1));
        scribe.setBar(bar);
        LibFeed.Feed[] memory feeds = _liftFeeds(bar);

        // Let privKey ∊ [1, Q).
        uint privKey = _bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Note to not lift feed.
        LibFeed.Feed memory feed = LibFeed.newFeed({privKey: privKey});

        // Don't run test if bad luck and feed already lifted.
        (bool isFeed, /*feedAddr*/ ) = scribe.feeds(feed.id);
        if (isFeed) return;

        // Let index ∊ [0, bar).
        uint index = _bound(indexSeed, 0, bar - 1);

        // Let non-lifted feed be the index's signer.
        feeds[index] = feed;

        bytes32 message = keccak256("scribe");

        bool ok = scribe.isAcceptableSchnorrSignatureNow(
            message, feeds.signSchnorr(message)
        );
        assertFalse(ok);
    }

    function testFuzz_isAcceptableSchnorrSignatureNow_FailsIf_SignatureInvalid(
        uint barSeed
    ) public {
        // Let bar ∊ [1, 256).
        uint8 bar = uint8(_bound(barSeed, 1, 256 - 1));
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
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        // Note to stay reasonable in favor of runtime.
        vm.assume(pokeDatas.length < 50);

        uint32 lastPokeTimestamp = 0;
        IScribe.SchnorrData memory schnorrData;
        for (uint i; i < pokeDatas.length; i++) {
            pokeDatas[i].val =
                uint128(_bound(pokeDatas[i].val, 1, type(uint128).max));
            pokeDatas[i].age = uint32(
                _bound(pokeDatas[i].age, lastPokeTimestamp + 1, block.timestamp)
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
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        vm.assume(pokeData.val != 0);
        // Let pokeData's age ∊ [1, block.timestamp].
        pokeData.age = uint32(_bound(pokeData.age, 1, block.timestamp));

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        // Poke once.
        scribe.poke(pokeData, schnorrData);

        // Last poke's age is set to block.timestamp.
        uint currentAge = uint32(block.timestamp);

        // Set pokeData's age ∊ [0, block.timestamp].
        pokeData.age = uint32(_bound(pokeData.age, 0, block.timestamp));

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
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        vm.assume(pokeData.val != 0);
        // Let pokeData's age ∊ [block.timestamp + 1, type(uint32).max].
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
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        // Let pokeData's val ∊ [1, type(uint128).max].
        // Let pokeData's age ∊ [1, block.timestamp].
        pokeData.val = uint128(_bound(pokeData.val, 1, type(uint128).max));
        pokeData.age = uint32(_bound(pokeData.age, 1, block.timestamp));

        // Create schnorrData signing different message.
        bytes32 message = keccak256("scribe");
        IScribe.SchnorrData memory schnorrData = feeds.signSchnorr(message);

        vm.expectRevert(IScribe.SchnorrSignatureInvalid.selector);
        scribe.poke(pokeData, schnorrData);
    }

    // -- Test: constructPokeMessage --

    function testFuzzDifferentialOracleSuite_constructPokeMessage(
        IScribe.PokeData memory pokeData
    ) public {
        bytes32 want = scribe.constructPokeMessage(pokeData);
        bytes32 got = LibOracleSuite.constructPokeMessage(
            scribe.wat(), pokeData.val, pokeData.age
        );
        assertEq(want, got);
    }

    // -- Test: Auth Protected Functions --

    function testFuzz_lift_Single(uint privKey) public {
        // Let privKey ∊ [1, Q).
        privKey = _bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        vm.expectEmit();
        emit FeedLifted(address(this), feed.pubKey.toAddress());

        uint feedId =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));
        assertEq(feedId, feed.id);

        // Is idempotent.
        scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));

        // Check via feeds(address)(bool).
        bool isFeed = scribe.feeds(feed.pubKey.toAddress());
        assertTrue(isFeed);

        // Check via feeds(uint8)(bool,address).
        address feedAddr;
        (isFeed, feedAddr) = scribe.feeds(feed.id);
        assertTrue(isFeed);
        assertEq(feedAddr, feed.pubKey.toAddress());

        // Check via feeds()(address[]).
        address[] memory feeds_ = scribe.feeds();
        assertEq(feeds_.length, 1);
        assertEq(feeds_[0], feed.pubKey.toAddress());
    }

    function test_lift_Single_FailsIf_ECDSADataInvalid() public {
        vm.expectRevert();
        scribe.lift(
            LibFeed.newFeed({privKey: 1}).pubKey,
            LibFeed.newFeed({privKey: 2}).signECDSA(FEED_REGISTRATION_MESSAGE)
        );
    }

    function test_lift_Single_FailsIf_FeedIdAlreadyLifted() public {
        LibFeed.Feed memory feed1 = LibFeed.newFeed({privKey: 22171});
        LibFeed.Feed memory feed2 = LibFeed.newFeed({privKey: 38091});

        // Both feeds have same id.
        assertTrue(feed1.id == feed2.id);

        scribe.lift(feed1.pubKey, feed1.signECDSA(FEED_REGISTRATION_MESSAGE));

        vm.expectRevert();
        scribe.lift(feed2.pubKey, feed2.signECDSA(FEED_REGISTRATION_MESSAGE));
    }

    function testFuzz_lift_Multiple(uint[] memory privKeys) public {
        vm.assume(privKeys.length < 50);

        // Let each privKey ∊ [1, Q).
        for (uint i; i < privKeys.length; i++) {
            privKeys[i] = _bound(privKeys[i], 1, LibSecp256k1.Q() - 1);
        }

        // Make at most one feed per id.
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](privKeys.length);
        uint bloom;
        uint ctr;
        for (uint i; i < privKeys.length; i++) {
            LibFeed.Feed memory feed = LibFeed.newFeed(privKeys[i]);

            if (bloom & (1 << feed.id) == 0) {
                bloom |= 1 << feed.id;

                feeds[ctr++] = feed;
            }
        }
        assembly ("memory-safe") {
            mstore(feeds, ctr)
        }

        // Make list of public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Make signatures.
        IScribe.ECDSAData[] memory ecdsaDatas =
            new IScribe.ECDSAData[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            ecdsaDatas[i] = feeds[i].signECDSA(FEED_REGISTRATION_MESSAGE);
        }

        // Expect events.
        for (uint i; i < feeds.length; i++) {
            vm.expectEmit();
            emit FeedLifted(address(this), feeds[i].pubKey.toAddress());
        }

        // Lift feeds and verify returned feed ids.
        uint8[] memory feedIds = scribe.lift(pubKeys, ecdsaDatas);
        assertEq(feedIds.length, feeds.length);
        for (uint i; i < feedIds.length; i++) {
            assertEq(feedIds[i], feeds[i].id);
        }

        // Check via feeds(address)(bool) and feeds(uint8)(bool,address).
        bool isFeed;
        uint8 feedId;
        address feedAddr;
        for (uint i; i < feeds.length; i++) {
            isFeed = scribe.feeds(feeds[i].pubKey.toAddress());
            assertTrue(isFeed);

            feedId = uint8(uint(uint160(feeds[i].pubKey.toAddress())) >> 152);

            (isFeed, feedAddr) = scribe.feeds(feedId);
            assertTrue(isFeed);
            assertEq(feeds[i].pubKey.toAddress(), feedAddr);
        }

        // Check via feeds()(address[]).
        address[] memory feedAddrs = scribe.feeds();
        for (uint i; i < feeds.length; i++) {
            for (uint j; j < feedAddrs.length; j++) {
                // Break inner loop if feed's address found in list of feedAddrs.
                if (feeds[i].pubKey.toAddress() == feedAddrs[j]) {
                    break;
                }

                // Fail if pubKey's address not found in list of feeds.
                if (j == feedAddrs.length - 1) {
                    fail("Expected feed missing in feeds()(address[])");
                }
            }
        }
    }

    function test_lift_Multiple_FailsIf_ECDSADataInvalid() public {
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](2);
        feeds[0] = LibFeed.newFeed({privKey: 1});
        feeds[1] = LibFeed.newFeed({privKey: 2});

        IScribe.ECDSAData[] memory ecdsaDatas = new IScribe.ECDSAData[](2);
        ecdsaDatas[0] = feeds[0].signECDSA(FEED_REGISTRATION_MESSAGE);
        ecdsaDatas[1] = ecdsaDatas[0];

        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](2);
        pubKeys[0] = feeds[0].pubKey;
        pubKeys[1] = feeds[1].pubKey;

        vm.expectRevert();
        scribe.lift(pubKeys, ecdsaDatas);
    }

    function testFuzz_lift_Multiple_FailsIf_ArrayLengthMismatch(
        LibSecp256k1.Point[] memory pubKeys,
        IScribe.ECDSAData[] memory ecdsaDatas
    ) public {
        vm.assume(pubKeys.length != ecdsaDatas.length);

        vm.expectRevert();
        scribe.lift(pubKeys, ecdsaDatas);
    }

    function testFuzz_drop_Single(uint privKey) public {
        // Let privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        uint8 feedId =
            scribe.lift(feed.pubKey, feed.signECDSA(FEED_REGISTRATION_MESSAGE));

        vm.expectEmit();
        emit FeedDropped(address(this), feed.pubKey.toAddress());

        scribe.drop(feedId);

        // Is idempotent.
        scribe.drop(feedId);

        // Check via feeds(address)(bool).
        bool isFeed = scribe.feeds(feed.pubKey.toAddress());
        assertFalse(isFeed);

        // Check via feeds(uint)(bool,address).
        address feedAddr;
        (isFeed, feedAddr) = scribe.feeds(feedId);
        assertFalse(isFeed);
        assertEq(feedAddr, address(0));

        // Check via feeds()(address[]).
        address[] memory feeds_ = scribe.feeds();
        assertEq(feeds_.length, 0);
    }

    function testFuzz_drop_Multiple(uint[] memory privKeys) public {
        // Let each privKey ∊ [1, Q).
        for (uint i; i < privKeys.length; i++) {
            privKeys[i] = _bound(privKeys[i], 1, LibSecp256k1.Q() - 1);
        }

        // Make at most one feed per id.
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](privKeys.length);
        uint bloom;
        uint ctr;
        for (uint i; i < privKeys.length; i++) {
            LibFeed.Feed memory feed = LibFeed.newFeed(privKeys[i]);

            if (bloom & (1 << feed.id) == 0) {
                bloom |= 1 << feed.id;

                feeds[ctr++] = feed;
            }
        }
        assembly ("memory-safe") {
            mstore(feeds, ctr)
        }

        // Make list of public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            pubKeys[i] = feeds[i].pubKey;
        }

        // Make signatures.
        IScribe.ECDSAData[] memory ecdsaDatas =
            new IScribe.ECDSAData[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            ecdsaDatas[i] = feeds[i].signECDSA(FEED_REGISTRATION_MESSAGE);
        }

        // Lift feeds.
        uint8[] memory feedIds = scribe.lift(pubKeys, ecdsaDatas);

        // Expect events.
        bloom = 0;
        ctr = 0;
        for (uint i; i < feeds.length; i++) {
            // Don't expect event for duplicates.
            if (bloom & (1 << feeds[i].id) == 0) {
                bloom |= 1 << feeds[i].id;

                vm.expectEmit();
                emit FeedDropped(address(this), feeds[i].pubKey.toAddress());
            }
        }

        // Drop feeds.
        scribe.drop(feedIds);

        // Is idempotent.
        scribe.drop(feedIds);

        // Check via feeds(address)(bool).
        bool isFeed;
        for (uint i; i < feeds.length; i++) {
            isFeed = scribe.feeds(feeds[i].pubKey.toAddress());
            assertFalse(isFeed);
        }

        // Check via feeds(uint8)(bool,address).
        address feedAddr;
        for (uint i; i < feeds.length; i++) {
            (isFeed, feedAddr) = scribe.feeds(feeds[i].id);
            assertFalse(isFeed);
            assertEq(feedAddr, address(0));
        }

        // Check via feeds()(address[]).
        address[] memory feedAddresses = scribe.feeds();
        assertEq(feedAddresses.length, 0);
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
        scribe.drop(new uint8[](1));
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

    function test_latestAnswer_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.latestAnswer();
    }
}
