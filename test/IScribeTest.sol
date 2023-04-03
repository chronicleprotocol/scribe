pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeAuth} from "src/IScribeAuth.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

/**
 * @notice Provides IScribe Unit Tests
 */
abstract contract IScribeTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribe scribe;

    bytes32 WAT;

    LibHelpers.Feed[] feeds;
    LibHelpers.Feed notFeed;

    function setUp(address scribe_) internal virtual {
        scribe = IScribe(scribe_);

        // Cache wat constant.
        WAT = scribe.wat();

        // Create and whitelist bar many feeds.
        LibHelpers.Feed[] memory feeds_ =
            LibHelpers.makeFeeds(1, IScribeAuth(address(scribe)).bar());
        for (uint i; i < feeds_.length; i++) {
            IScribeAuth(address(scribe)).lift(feeds_[i].pubKey);

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

        // Peeking returns false.
        (uint val, bool ok) = scribe.peek();
        assertEq(val, 0); // Note that this behaviour is actually not defined.
        assertFalse(ok);

        // Reading fails.
        try scribe.read() returns (uint) {
            assertTrue(false);
        } catch {}
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

        uint bar = IScribeAuth(address(scribe)).bar();
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

        uint bar = IScribeAuth(address(scribe)).bar();

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
