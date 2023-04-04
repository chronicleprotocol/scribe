pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

/**
 * @notice Provides IScribe Unit Tests
 */
abstract contract IScribeTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribe private scribe;

    bytes32 internal WAT;

    LibHelpers.Feed[] internal feeds;
    LibHelpers.Feed internal notFeed;

    mapping(address => bool) internal addressFilter;

    // Events copied from IScribe.
    // @todo Add missing events + test for emission.
    event Poked(address indexed caller, uint128 val, uint32 age);
    event FeedLifted(address indexed caller, address indexed feed);
    event FeedDropped(address indexed caller, address indexed feed);
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    function setUp(address scribe_) internal virtual {
        scribe = IScribe(scribe_);

        // Cache wat constant.
        WAT = scribe.wat();

        // Create and whitelist bar many feeds.
        LibHelpers.Feed[] memory feeds_ = LibHelpers.makeFeeds(1, scribe.bar());
        for (uint i; i < feeds_.length; i++) {
            scribe.lift(
                feeds_[i].pubKey,
                LibHelpers.makeECDSASignature(
                    feeds_[i], scribe.feedLiftMessage()
                )
            );

            // Note to copy feed individually to prevent
            // "UnimplementedFeatureError" when compiling without --via-ir.
            feeds.push(feeds_[i]);
        }

        // Create not feed.
        notFeed = LibHelpers.makeFeed({privKey: 0xdead});

        // Toll address(this).
        IToll(address(scribe)).kiss(address(this));
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

        // Set of feeds empty.
        assertEq(scribe.feeds().length, 0);

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
                          TEST: POKE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_poke_Initial(IScribe.PokeData memory pokeData) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        scribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT)
        );

        assertEq(scribe.read(), pokeData.val);
        (uint val, bool ok) = scribe.peek();
        assertEq(val, pokeData.val);
        assertTrue(ok);
    }

    function test_poke_Initial_FailsIf_AgeIsZero() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 0;

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.StaleMessage.selector, 0, 0)
        );
        scribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT)
        );
    }

    function testFuzz_poke_Continuously(IScribe.PokeData[] memory pokeDatas)
        public
    {
        // Ensure pokeDatas' val is never zero and their age is strictly
        // increasing.
        uint32 lastAge = uint32(block.timestamp);
        for (uint i; i < pokeDatas.length; i++) {
            vm.assume(pokeDatas[i].val != 0);

            // Upper bound age to lastAge + 1 weeks to no run into overflow.
            // Note that this does not guarantee overflow safety.
            // @todo Fix overflow danger if necessary.
            pokeDatas[i].age =
                uint32(bound(pokeDatas[i].age, lastAge + 1, lastAge + 1 weeks));

            lastAge = pokeDatas[i].age;
        }

        for (uint i; i < pokeDatas.length; i++) {
            scribe.poke(
                pokeDatas[i],
                LibHelpers.makeSchnorrSignature(feeds, pokeDatas[i], WAT)
            );

            assertEq(scribe.read(), pokeDatas[i].val);
            (uint val, bool ok) = scribe.peek();
            assertEq(val, pokeDatas[i].val);
            assertTrue(ok);
        }
    }

    function testFuzz_poke_FailsIf_PokeData_IsStale(
        IScribe.PokeData memory pokeData
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        // Poke once.
        scribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT)
        );

        // Last poke's age is set to block.timestamp.
        uint currentAge = uint32(block.timestamp);

        // Poke again with age ∊ [0, block.timestamp].
        pokeData.age = uint32(bound(pokeData.age, 0, block.timestamp));
        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.StaleMessage.selector, pokeData.age, currentAge
            )
        );
        scribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT)
        );
    }

    function testFuzz_poke_FailsIf_SchnorrSignatureData_HasInsufficientNumberOfSigners(
        IScribe.PokeData memory pokeData,
        uint numberSignersSeed
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = scribe.bar();
        uint numberSigners = bound(numberSignersSeed, 0, bar - 1);

        // Create set of feeds with less than bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](numberSigners);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.BarNotReached.selector, uint8(numberSigners), bar
            )
        );
        scribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds_, pokeData, WAT)
        );
    }

    function testFuzz_poke_FailsIf_SchnorrSignatureData_HasNonOrderedSigners(
        IScribe.PokeData memory pokeData,
        uint duplicateIndexSeed
    ) public {
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

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.SignersNotOrdered.selector)
        );
        scribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds_, pokeData, WAT)
        );
    }

    function test_poke_FailsIf_SchnorrSignatureData_HasNonFeedAsSigner()
        public
    {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        // Add non-feed to feeds.
        feeds.push(notFeed);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.SignerNotFeed.selector, notFeed.pubKey.toAddress()
            )
        );
        scribe.poke(pokeData, schnorrSignatureData);
    }

    function test_poke_FailsIf_SchnorrSignatureData_FailsSignatureVerification()
        public
    {
        // @todo Implement once Schnorr signature verification enabled.
        console2.log("NOT IMPLEMENTED");
    }

    /*//////////////////////////////////////////////////////////////
                     TEST: AUTH PROTECTED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_lift_Single(uint privKey) public {
        // Bound private key to secp256k1's order, i.e. scalar ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibHelpers.Feed memory feed = LibHelpers.makeFeed(privKey);

        vm.expectEmit(true, true, true, true);
        emit FeedLifted(address(this), feed.pubKey.toAddress());

        scribe.lift(
            feed.pubKey,
            LibHelpers.makeECDSASignature(feed, scribe.feedLiftMessage())
        );

        // Check via feeds(address)(bool).
        assertTrue(scribe.feeds(feed.pubKey.toAddress()));

        // Check via feeds()(address[]).
        address[] memory feeds_ = scribe.feeds();
        assertEq(feeds_.length, 1);
        assertEq(feeds_[0], feed.pubKey.toAddress());
    }

    function test_lift_Single_FailsIf_PubKeyIsZero() public {
        LibSecp256k1.Point memory zeroPoint = LibSecp256k1.Point(0, 0);

        vm.expectRevert();
        scribe.lift(zeroPoint, IScribe.ECDSASignatureData(0, 0, 0));
    }

    function testFuzz_lift_Multiple(uint[] memory privKeys) public {
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
            ecdsaDatas[i] = LibHelpers.makeECDSASignature(
                feeds_[i], scribe.feedLiftMessage()
            );
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

        // Check via feeds(address)(bool).
        for (uint i; i < pubKeys.length; i++) {
            assertTrue(scribe.feeds(pubKeys[i].toAddress()));
        }

        // Check via feeds()(address[]).
        address[] memory feedsAddrs = scribe.feeds();
        for (uint i; i < pubKeys.length; i++) {
            for (uint j; j < feedsAddrs.length; j++) {
                // Break inner loop if pubKey found in list of feeds.
                if (pubKeys[i].toAddress() == feedsAddrs[j]) {
                    break;
                }

                // Fail if pubKey not found in list of feeds.
                if (j == feedsAddrs.length - 1) {
                    assertTrue(false);
                }
            }
        }
    }

    /*
    // @todo Fix tests lift/drop.
    function test_lift_Multiple_FailsIf_PubKeyIsZero() public {
        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](3);

        // Zero point as first element.
        pubKeys[0] = LibSecp256k1.Point(0, 0);
        pubKeys[1] = LibSecp256k1.Point(1, 1);
        pubKeys[2] = LibSecp256k1.Point(1, 1);
        vm.expectRevert();
        scribe.lift(pubKeys);

        // Zero point as middle element.
        pubKeys[0] = LibSecp256k1.Point(1, 1);
        pubKeys[1] = LibSecp256k1.Point(0, 0);
        pubKeys[2] = LibSecp256k1.Point(1, 1);
        vm.expectRevert();
        scribe.lift(pubKeys);

        // Zero point as last element.
        pubKeys[0] = LibSecp256k1.Point(1, 1);
        pubKeys[1] = LibSecp256k1.Point(1, 1);
        pubKeys[2] = LibSecp256k1.Point(0, 0);
        vm.expectRevert();
        scribe.lift(pubKeys);
    }

    function testFuzz_drop_Single(LibSecp256k1.Point memory pubKey) public {
        vm.assume(!pubKey.isZeroPoint());

        scribe.lift(pubKey);

        vm.expectEmit(true, true, true, true);
        emit FeedDropped(address(this), pubKey.toAddress());

        scribe.drop(pubKey);

        // Check via feeds(address)(bool).
        assertFalse(scribe.feeds(pubKey.toAddress()));

        // Check via feeds()(address[]).
        assertEq(scribe.feeds().length, 0);
    }

    function testFuzz_drop_Multiple(LibSecp256k1.Point[] memory pubKeys)
        public
    {
        for (uint i; i < pubKeys.length; i++) {
            vm.assume(!pubKeys[i].isZeroPoint());
        }

        scribe.lift(pubKeys);

        for (uint i; i < pubKeys.length; i++) {
            // Don't expect event for duplicates.
            if (!addressFilter[pubKeys[i].toAddress()]) {
                vm.expectEmit(true, true, true, true);
                emit FeedDropped(address(this), pubKeys[i].toAddress());
            }

            addressFilter[pubKeys[i].toAddress()] = true;
        }

        scribe.drop(pubKeys);

        // Check via feeds(address)(bool).
        for (uint i; i < pubKeys.length; i++) {
            assertFalse(scribe.feeds(pubKeys[i].toAddress()));
        }

        // Check via feeds()(address[]).
        assertEq(scribe.feeds().length, 0);
    }

    function test_liftDropLift(LibSecp256k1.Point memory pubKey) public {
        vm.assume(!pubKey.isZeroPoint());

        scribe.lift(LibSecp256k1.Point(1, 1));

        scribe.lift(pubKey);
        assertTrue(scribe.feeds(pubKey.toAddress()));
        assertEq(scribe.feeds().length, 2);

        scribe.drop(pubKey);
        assertFalse(scribe.feeds(pubKey.toAddress()));
        assertEq(scribe.feeds().length, 1);

        scribe.lift(pubKey);
        assertTrue(scribe.feeds(pubKey.toAddress()));

        // Note that the list returned via feeds()(address[]) is allowed to
        // contain duplicates.
        address[] memory feeds_ = scribe.feeds();
        assertEq(feeds_.length, 3);
        assertEq(feeds_[0], LibSecp256k1.Point(1, 1).toAddress());
        assertEq(feeds_[1], pubKey.toAddress());
        assertEq(feeds_[2], pubKey.toAddress());
    }
    */

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
