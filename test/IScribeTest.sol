pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe_Optimized as IScribe} from "src/IScribe_Optimized.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

/**
 * @notice Provides IScribe Unit Tests
 */
abstract contract IScribeTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    IScribe private scribe;

    bytes32 internal WAT;
    bytes32 internal WAT_MESSAGE;

    LibFeed.Feed[] internal feeds;
    LibFeed.Feed internal notFeed;

    mapping(address => bool) internal addressFilter;

    // Events copied from IScribe.
    // @todo Add missing events + test for emission.
    event Poked(address indexed caller, uint128 val, uint32 age);
    event FeedLifted(address indexed caller, address indexed feed);
    event FeedDropped(address indexed caller, address indexed feed);
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    function setUp(address scribe_) internal virtual {
        // @todo Deploy via script.
        scribe = IScribe(scribe_);

        // Cache constants.
        WAT = scribe.wat();
        WAT_MESSAGE = scribe.watMessage();

        // Toll address(this).
        IToll(address(scribe)).kiss(address(this));
    }

    /// @dev Creates and lift `scribe.bar()` many feeds.
    ///      Also creates a non-feed key pair instance.
    function _setUp_liftFeeds() internal {
        // Create and lift bar many feeds.
        uint bar = scribe.bar();
        LibFeed.Feed memory feed;
        for (uint i; i < bar; i++) {
            feed = LibFeed.newFeed({privKey: i + 1, index: uint8(i + 1)});
            vm.label(
                feed.pubKey.toAddress(),
                string.concat("Feed #", vm.toString(i + 1))
            );

            feeds.push(feed);
            scribe.lift(feed.pubKey, feed.signECDSA(WAT_MESSAGE));
        }

        // Create a non-feed instance.
        notFeed = LibFeed.newFeed({privKey: 0xdead, index: type(uint8).max});
    }

    /*//////////////////////////////////////////////////////////////
                            TEST: DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public virtual {
        // Deployer is auth'ed.
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

        // tryRead()(bool,uint) returns false.
        (ok, val) = scribe.tryRead();
        assertEq(val, 0);
        assertFalse(ok);

        // peek()(uint,bool) returns false.
        // Note that peek()(uint,bool) is deprecated.
        (val, ok) = scribe.peek();
        assertEq(val, 0);
        assertFalse(ok);
    }

    /*//////////////////////////////////////////////////////////////
                       TEST: SCHNORR VERIFICATION
    //////////////////////////////////////////////////////////////*/

    // @todo Fuzz LibSchnorrExtended::verify against LibSchnorr::verify.

    function testFuzz_verifySignature(bytes32 message) public {
        _setUp_liftFeeds();

        bool ok;
        bytes memory err;
        // forgefmt: disable-next-item
        (ok, err) = scribe.verifySchnorrSignature(
            message,
            feeds.signSchnorr(message)
        );
        assertTrue(ok);
        assertEq(err.length, 0);
    }

    // @todo More than 32/64/96/128... signers
    // @todo schnorrData.signersBlob.length == bar BUT actual length < bar.

    /*//////////////////////////////////////////////////////////////
                          TEST: POKE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_poke(IScribe.PokeData[] memory pokeDatas) public {
        _setUp_liftFeeds();

        // Ensure pokeDatas' val is never zero and pokeData's age is greater
        // than block.timestamp. Note that block.timestamp is not increased
        // in this test, so it is sufficient to ensure each age is newer than
        // the last one. Note that Scribe sets a pokeData's age to
        // block.timestamp.
        for (uint i; i < pokeDatas.length; i++) {
            vm.assume(pokeDatas[i].val != 0);
            vm.assume(pokeDatas[i].age > uint32(block.timestamp));
        }

        IScribe.SchnorrSignatureData memory schnorrData;
        for (uint i; i < pokeDatas.length; i++) {
            schnorrData =
                feeds.signSchnorr(scribe.constructPokeMessage(pokeDatas[i]));

            scribe.poke(pokeDatas[i], schnorrData);

            assertEq(scribe.read(), pokeDatas[i].val);
            (bool ok, uint val) = scribe.tryRead();
            assertEq(val, pokeDatas[i].val);
            assertTrue(ok);
        }
    }

    function test_poke_Initial_FailsIf_AgeIsZero() public {
        _setUp_liftFeeds();

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 0;

        IScribe.SchnorrSignatureData memory schnorrData;
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.StaleMessage.selector, 0, 0)
        );
        scribe.poke(pokeData, schnorrData);
    }

    function testFuzz_poke_FailsIf_PokeData_IsStale(
        IScribe.PokeData memory pokeData
    ) public {
        _setUp_liftFeeds();

        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrData;
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

    /*
    function testFuzz_poke_FailsIf_SchnorrSignatureData_HasInsufficientNumberOfSigners(
        IScribe.PokeData memory pokeData,
        uint numberSignersSeed
    ) public {
        _setUp_liftFeeds();

        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = scribe.bar();
        uint numberSigners = bound(numberSignersSeed, 0, bar - 1);

        // Make set of feed key pairs with less than bar elements.
        LibCommon.KeyPair[] memory feeds_ =
            new LibCommon.KeyPair[](numberSigners);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        IScribe.SchnorrSignatureData memory schnorrData;
        // @todo SchnorrSignatureData via LibCommon?
        //schnorrData = feeds_.schnorrSign(scribe, pokeData);

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.BarNotReached.selector, uint8(numberSigners), bar
            )
        );
        scribe.poke(pokeData, schnorrData);
    }

    function testFuzz_poke_FailsIf_SchnorrSignatureData_HasNonOrderedSigners(
        IScribe.PokeData memory pokeData,
        uint duplicateIndexSeed
    ) public {
        _setUp_liftFeeds();

        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = scribe.bar();

        // Create set of feeds with bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](bar);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        // But have the first feed two times in the set.
        uint index = bound(duplicateIndexSeed, 1, feeds_.length - 1);
        feeds_[index] = feeds_[0];

        IScribe.SchnorrSignatureData memory schnorrData;
        schnorrData = feeds_.signSchnorrMessage(scribe, pokeData);

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.SignersNotOrdered.selector)
        );
        scribe.poke(pokeData, schnorrData);
    }

    function testFuzz_poke_FailsIf_SchnorrSignatureData_HasNonFeedAsSigner(
        IScribe.PokeData memory pokeData,
        uint nonFeedIndexSeed
    ) public {
        _setUp_liftFeeds();

        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = scribe.bar();

        // Create set of feeds with bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](bar);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        // But have a non-feed in the set.
        uint index = bound(nonFeedIndexSeed, 1, feeds_.length - 1);
        feeds_[index] = notFeed;

        IScribe.SchnorrSignatureData memory schnorrData;
        schnorrData = feeds_.signSchnorrMessage(scribe, pokeData);

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.SignerNotFeed.selector, notFeed.pubKey.toAddress()
            )
        );
        scribe.poke(pokeData, schnorrData);
    }

    function test_poke_FailsIf_SchnorrSignatureData_FailsSignatureVerification()
        public
    {
        _setUp_liftFeeds();

        // @todo Implement once Schnorr signature verification enabled.
        console2.log("NOT IMPLEMENTED");
    }

    */
    /*//////////////////////////////////////////////////////////////
                     TEST: AUTH PROTECTED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_lift_Single(uint privKey) public {
        // Bound private key to secp256k1's order, i.e. scalar ∊ [1, Q).
        uint privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        vm.expectEmit(true, true, true, true);
        emit FeedLifted(address(this), feed.pubKey.toAddress());

        scribe.lift(feed.pubKey, feed.signECDSA(WAT_MESSAGE));

        // Check via feeds(address)(bool).
        bool ok;
        uint index;
        (ok, index) = scribe.feeds(feed.pubKey.toAddress());
        assertTrue(ok);
        assertEq(index, 1);

        // Check via feeds()(address[],uint[]).
        address[] memory feeds_;
        uint[] memory indexes;
        (feeds_, indexes) = scribe.feeds();
        assertEq(feeds_.length, indexes.length);
        assertEq(feeds_.length, 1);
        assertEq(feeds_[0], feed.pubKey.toAddress());
        assertEq(indexes[0], 1);
    }

    function test_lift_Single_FailsIf_PubKeyIsZero() public {
        vm.expectRevert();
        scribe.lift(
            LibSecp256k1.ZERO_POINT(), IScribe.ECDSASignatureData(0, 0, 0)
        );
    }

    function testFuzz_lift_Multiple(uint[] memory privKeys) public {
        // Bound private keys to secp256k1's order, i.e. scalar ∊ [1, Q).
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
        IScribe.ECDSASignatureData[] memory ecdsaDatas =
            new IScribe.ECDSASignatureData[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            ecdsaDatas[i] = feeds_[i].signECDSA(WAT_MESSAGE);
        }

        for (uint i; i < feeds_.length; i++) {
            // Don't expect event for duplicates.
            if (!addressFilter[feeds_[i].pubKey.toAddress()]) {
                vm.expectEmit(true, true, true, true);
                emit FeedLifted(address(this), feeds_[i].pubKey.toAddress());
            }
            addressFilter[feeds_[i].pubKey.toAddress()] = true;
        }

        scribe.lift(pubKeys, ecdsaDatas);

        // Check via feeds(address)(bool,uint).
        bool ok;
        uint index;
        for (uint i; i < pubKeys.length; i++) {
            (ok, index) = scribe.feeds(pubKeys[i].toAddress());
            assertTrue(ok);

            // Note that the indexes are orders based on pubKeys' addresses.
            assertTrue(index != 0);
        }

        // Check via feeds()(address[],uint[]).
        address[] memory addrs;
        uint[] memory indexes;
        (addrs, indexes) = scribe.feeds();
        for (uint i; i < pubKeys.length; i++) {
            for (uint j; j < addrs.length; j++) {
                // Break inner loop if pubKey found in list of feeds.
                if (pubKeys[i].toAddress() == addrs[j]) {
                    break;
                }

                // Fail if pubKey not found in list of feeds.
                if (j == addrs.length - 1) {
                    assertTrue(false);
                }
            }
        }
    }

    function test_lift_Multiple_FailsIf_PubKeyIsZero() public {
        vm.expectRevert();
        scribe.lift(
            new LibSecp256k1.Point[](1), new IScribe.ECDSASignatureData[](1)
        );
    }

    /*
    function testFuzz_drop_Single(uint privKey) public {
        // Bound private key to secp256k1's order, i.e. scalar ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibHelpers.Feed memory feed = LibHelpers.makeFeed(privKey);

        scribe.lift(
            feed.pubKey, LibHelpers.makeECDSASignature(feed, WAT_MESSAGE)
        );

        vm.expectEmit(true, true, true, true);
        emit FeedDropped(address(this), feed.pubKey.toAddress());

        scribe.drop(feed.pubKey);

        // Check via feeds(address)(bool).
        assertFalse(scribe.feeds(feed.pubKey.toAddress()));

        // Check via feeds()(address[]).
        assertEq(scribe.feeds().length, 0);
    }

    function testFuzz_drop_Multiple(uint[] memory privKeys) public {
        // Bound private keys to secp256k1's order, i.e. scalar ∊ [1, Q).
        for (uint i; i < privKeys.length; i++) {
            privKeys[i] = bound(privKeys[i], 1, LibSecp256k1.Q() - 1);
        }

        // Make feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](privKeys.length);
        for (uint i; i < privKeys.length; i++) {
            feeds_[i] = LibHelpers.makeFeed(privKeys[i]);
        }

        // Make list of public keys.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            pubKeys[i] = feeds_[i].pubKey;
        }

        // Make signatures.
        IScribe.ECDSASignatureData[] memory ecdsaDatas =
            new IScribe.ECDSASignatureData[](feeds_.length);
        for (uint i; i < feeds_.length; i++) {
            ecdsaDatas[i] =
                LibHelpers.makeECDSASignature(feeds_[i], WAT_MESSAGE);
        }

        // Lift feeds.
        scribe.lift(pubKeys, ecdsaDatas);

        // Expect events.
        for (uint i; i < pubKeys.length; i++) {
            // Don't expect event for duplicates.
            if (!addressFilter[pubKeys[i].toAddress()]) {
                vm.expectEmit(true, true, true, true);
                emit FeedDropped(address(this), pubKeys[i].toAddress());
            }

            addressFilter[pubKeys[i].toAddress()] = true;
        }

        // Drop feeds.
        scribe.drop(pubKeys);

        // Check via feeds(address)(bool).
        for (uint i; i < pubKeys.length; i++) {
            assertFalse(scribe.feeds(pubKeys[i].toAddress()));
        }

        // Check via feeds()(address[]).
        assertEq(scribe.feeds().length, 0);
    }

    function testFuzz_liftDropLift(uint privKey) public {
        // Bound private key to secp256k1's order, i.e. scalar ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibHelpers.Feed memory feed = LibHelpers.makeFeed(privKey);

        IScribe.ECDSASignatureData memory ecdsaData =
            LibHelpers.makeECDSASignature(feed, WAT_MESSAGE);

        scribe.lift(feed.pubKey, ecdsaData);
        assertTrue(scribe.feeds(feed.pubKey.toAddress()));
        assertEq(scribe.feeds().length, 1);

        scribe.drop(feed.pubKey);
        assertFalse(scribe.feeds(feed.pubKey.toAddress()));
        assertEq(scribe.feeds().length, 0);

        scribe.lift(feed.pubKey, ecdsaData);
        assertTrue(scribe.feeds(feed.pubKey.toAddress()));

        // Note that the list returned via feeds()(address[]) is allowed to
        // contain duplicates.
        address[] memory feeds_ = scribe.feeds();
        assertEq(feeds_.length, 2);
        assertEq(feeds_[0], feed.pubKey.toAddress());
        assertEq(feeds_[1], feed.pubKey.toAddress());
    }

    function testFuzz_setBar(uint8 bar) public {
        vm.assume(bar != 0);

        // Only expect event if bar actually changes.
        if (bar != scribe.bar()) {
            vm.expectEmit(true, true, true, true);
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
        scribe.lift(
            LibSecp256k1.Point(0, 0), IScribe.ECDSASignatureData(0, 0, 0)
        );
    }

    function test_lift_Multiple_IsAuthProtected() public {
        LibSecp256k1.Point[] memory pubKeys;
        IScribe.ECDSASignatureData[] memory ecdsaDatas;

        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.lift(pubKeys, ecdsaDatas);
    }

    function test_drop_Single_IsAuthProtected() public {
        LibSecp256k1.Point memory zeroPoint = LibSecp256k1.Point(0, 0);

        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.drop(zeroPoint);
    }

    function test_drop_Multiple_IsAuthProtected() public {
        LibSecp256k1.Point[] memory pubKeys;

        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.drop(pubKeys);
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
    */

    /*//////////////////////////////////////////////////////////////
                     TEST: TOLL PROTECTED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_read_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.read();
    }

    function test_peek_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribe.peek();
    }
}
