pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeTest} from "./IScribeTest.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

/**
 * @notice Provides IScribeOptimistic Unit Tests
 */
abstract contract IScribeOptimisticTest is IScribeTest {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    IScribeOptimistic private opScribe;

    // Events copied from IScribeOptimistic.
    event OpPoked(
        address indexed caller,
        address indexed opFeed,
        IScribe.SchnorrData schnorrData,
        IScribe.PokeData pokeData
    );
    event OpPokeChallengedSuccessfully(
        address indexed caller, bytes schnorrErr
    );
    event OpPokeChallengedUnsuccessfully(address indexed caller);
    event OpChallengeRewardPaid(address indexed challenger, uint reward);
    event OpPokeDataDropped(address indexed caller, IScribe.PokeData pokeData);
    event OpChallengePeriodUpdated(
        address indexed caller,
        uint16 oldOpChallengePeriod,
        uint16 newOpChallengePeriod
    );
    event MaxChallengeRewardUpdated(
        address indexed caller,
        uint oldMaxChallengeReward,
        uint newMaxChallengeReward
    );

    function setUp(address scribe_) internal override(IScribeTest) {
        super.setUp(scribe_);

        opScribe = IScribeOptimistic(scribe_);
    }

    // Necessary to receive opChallenge rewards.
    receive() external payable {}

    //--------------------------------------------------------------------------
    // Test: Deployment

    function test_Deployment() public override(IScribeTest) {
        super.test_Deployment();

        // opFeedIndex not set.
        assertEq(opScribe.opFeedIndex(), 0);

        // OpChallengePeriod set to 1 hour.
        assertEq(opScribe.opChallengePeriod(), 1 hours);
    }

    //--------------------------------------------------------------------------
    // Test: opPoke

    function testFuzz_opPoke(
        IScribe.PokeData[] memory pokeDatas,
        uint[] memory feedIndexSeeds
    ) public {
        // vm.assume(pokeData.length < 50)
        if (pokeDatas.length > 50) {
            assembly ("memory-safe") {
                mstore(pokeDatas, 50)
            }
        }
        // vm.assume(pokeDatas.length == feedIndexSeeds.length);
        uint pokeDatasLen = pokeDatas.length;
        uint feedIndexSeedsLen = feedIndexSeeds.length;
        if (pokeDatasLen > feedIndexSeedsLen) {
            assembly ("memory-safe") {
                mstore(pokeDatas, feedIndexSeedsLen)
            }
        } else {
            assembly ("memory-safe") {
                mstore(feedIndexSeeds, pokeDatasLen)
            }
        }

        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.SchnorrData memory schnorrData;
        IScribe.ECDSAData memory ecdsaData;
        uint feedIndex;
        for (uint i; i < pokeDatas.length; i++) {
            // Select random feed signing opPoke.
            feedIndex = bound(feedIndexSeeds[i], 0, feeds.length - 1);

            // Make sure val is non-zero and age not stale.
            pokeDatas[i].val =
                uint128(bound(pokeDatas[i].val, 1, type(uint128).max));
            pokeDatas[i].age = uint32(block.timestamp);

            // Schnorr multi-sign pokeData with feeds.
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeDatas[i]));

            // ECDSA single-sign (pokeData, schnorrData).
            ecdsaData = feeds[feedIndex].signECDSA(
                opScribe.constructOpPokeMessage(pokeDatas[i], schnorrData)
            );

            // Execute opPoke.
            opScribe.opPoke(pokeDatas[i], schnorrData, ecdsaData);

            // Wait until challenge period over and opPokeData finalizes.
            vm.warp(block.timestamp + opScribe.opChallengePeriod());

            // Check that value can be read.
            assertEq(opScribe.read(), pokeDatas[i].val);
        }
    }

    function test_opPoke_Initial_FailsIf_AgeIsZero() public {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 0;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.StaleMessage.selector, 0, 0)
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opPoke_FailsIf_AgeIsStale(
        IScribe.PokeData memory pokeData
    ) public {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Set pokeData's age ∊ [0, block.timestamp].
        pokeData.age = uint32(bound(pokeData.age, 0, block.timestamp));

        uint lastAge = uint32(block.timestamp);

        // Wait until opPokeData finalized.
        vm.warp(block.timestamp + opScribe.opChallengePeriod());

        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.StaleMessage.selector, pokeData.age, lastAge
            )
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opPoke_FailsIf_ECDSASignatureInvalid(
        bool vSeed,
        uint rMask,
        uint sMask
    ) public {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Mutate ECDSA signature. Make sure to actually mutate though.
        if ((ecdsaData.v == 27) == vSeed) rMask |= 1;
        ecdsaData.v = vSeed ? 27 : 28;
        ecdsaData.r = bytes32(uint(ecdsaData.r) ^ rMask);
        ecdsaData.s = bytes32(uint(ecdsaData.s) ^ sMask);

        // Get address expected to be recovered.
        address recovered = ecrecover(
            opScribe.constructOpPokeMessage(pokeData, schnorrData),
            ecdsaData.v,
            ecdsaData.r,
            ecdsaData.s
        );

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.SignerNotFeed.selector, recovered)
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opPoke_FailsIf_opPokeDataInChallengePeriodExists(
        uint warpSeed
    ) public {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // opPoke once.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Wait for some time less than opChallengePeriod.
        vm.warp(
            block.timestamp
                + bound(warpSeed, 0, opScribe.opChallengePeriod() - 1)
        );

        vm.expectRevert(IScribeOptimistic.InChallengePeriod.selector);
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    //--------------------------------------------------------------------------
    // Test: opChallenge

    function testFuzz_opChallenge_opPokeDataValidAndNotStale(uint warpSeed)
        public
    {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute valid opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Wait for some time less than opChallengePeriod.
        vm.warp(
            block.timestamp
                + bound(warpSeed, 0, opScribe.opChallengePeriod() - 1)
        );

        uint balanceBefore = address(this).balance;

        // Challenge opPoke.
        bool opPokeInvalid = opScribe.opChallenge(schnorrData);

        // opPoke not invalid.
        assertFalse(opPokeInvalid);

        // No reward paid.
        assertEq(address(this).balance, balanceBefore);

        // opPokeData finalized.
        assertEq(opScribe.read(), pokeData.val);
    }

    function testFuzz_opChallenge_opPokeDataValidButStale(uint warpSeed)
        public
    {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute valid opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Wait for some time less than opChallengePeriod.
        vm.warp(
            block.timestamp
                + bound(warpSeed, 0, opScribe.opChallengePeriod() - 1)
        );

        // Execute poke, making the opPoke stale.
        IScribe.PokeData memory pokeDataNew;
        pokeDataNew.val = 2;
        pokeDataNew.age = uint32(block.timestamp);
        opScribe.poke(
            pokeDataNew,
            feeds.signSchnorr(opScribe.constructPokeMessage(pokeDataNew))
        );

        // Challenge opPoke.
        bool opPokeInvalid = opScribe.opChallenge(schnorrData);

        uint balanceBefore = address(this).balance;

        // opPoke not invalid.
        assertFalse(opPokeInvalid);

        // No reward paid.
        assertEq(address(this).balance, balanceBefore);

        // opPokeData not finalized.
        assertEq(opScribe.read(), pokeDataNew.val);
    }

    function testFuzz_opChallenge_opPokeDataInvalid(
        uint warpSeed,
        uint schnorrSignatureMask,
        uint160 schnorrCommitmentMask
    ) public {
        vm.assume(schnorrSignatureMask != 0 || schnorrCommitmentMask != 0);

        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        // Mutate schnorrData.
        schnorrData.signature =
            bytes32(uint(schnorrData.signature) ^ schnorrSignatureMask);
        schnorrData.commitment =
            address(uint160(schnorrData.commitment) ^ schnorrCommitmentMask);

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Deal 1 ETH to opScribe...
        vm.deal(address(opScribe), 1 ether);
        // ...and set maxChallengeReward to 1 ether.
        opScribe.setMaxChallengeReward(1 ether);

        // Execute invalid opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Wait for some time less than opChallengePeriod.
        vm.warp(
            block.timestamp
                + bound(warpSeed, 0, opScribe.opChallengePeriod() - 1)
        );

        uint balanceBefore = address(this).balance;

        // Challenge opPoke.
        bool opPokeInvalid = opScribe.opChallenge(schnorrData);

        // opPoke invalid.
        assertTrue(opPokeInvalid);

        // opFeed dropped.
        (bool isFeed,) = opScribe.feeds(feeds[0].pubKey.toAddress());
        assertFalse(isFeed);

        // 1 ETH reward paid.
        assertEq(address(this).balance, balanceBefore + 1 ether);
        assertEq(address(opScribe).balance, 0);

        // opPokeData not finalized.
        (bool ok,) = opScribe.tryRead();
        assertFalse(ok);
    }

    function test_opChallenge_FailsIf_NoOpPokeToChallenge() public {
        IScribe.SchnorrData memory schnorrData;

        vm.expectRevert(IScribeOptimistic.NoOpPokeToChallenge.selector);
        opScribe.opChallenge(schnorrData);
    }

    function test_opChallenge_FailsIf_InvalidSchnorrDataGiven() public {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Mutate schnorrData.
        unchecked {
            schnorrData.signature = bytes32(uint(schnorrData.signature) + 1);
        }

        vm.expectRevert();
        opScribe.opChallenge(schnorrData);
    }

    //--------------------------------------------------------------------------
    // Test: Auth Protected Functions

    function testFuzz_setOpChallengePeriod(uint16 opChallengePeriod) public {
        vm.assume(opChallengePeriod != 0);

        // Only expect event if opChallengePeriod actually changes.
        if (opChallengePeriod != opScribe.opChallengePeriod()) {
            vm.expectEmit();
            emit OpChallengePeriodUpdated(
                address(this), opScribe.opChallengePeriod(), opChallengePeriod
            );
        }

        opScribe.setOpChallengePeriod(opChallengePeriod);

        assertEq(opScribe.opChallengePeriod(), opChallengePeriod);
    }

    function test_setOpChallengePeriod_FailsIf_OpChallengePeriodIsZero()
        public
    {
        vm.expectRevert();
        opScribe.setOpChallengePeriod(0);
    }

    function test_setOpChallengePeriod_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        opScribe.setOpChallengePeriod(0);
    }

    // @todo isAfterAuthedActionProtected needs following tests:
    //          - delete opPOkeData if not finalized
    //          - not deletes opPokeData if finalized
    //          - sets age of current val to block.timestamp
    //              -> check via expect(isStale)

    function test_setOpChallengePeriod_IsAfterAuthedActionProtected() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        _setUpFeedsAndOpPokeOnce(pokeData);

        vm.expectEmit();
        emit OpPokeDataDropped(address(this), pokeData);

        opScribe.setOpChallengePeriod(1);
    }

    function test_drop_Single_IsAfterAuthedActionProtected() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        _setUpFeedsAndOpPokeOnce(pokeData);

        vm.expectEmit();
        emit OpPokeDataDropped(address(this), pokeData);

        opScribe.drop(1);
    }

    function test_drop_Multiple_IsAfterAuthedActionProtected() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        _setUpFeedsAndOpPokeOnce(pokeData);

        vm.expectEmit();
        emit OpPokeDataDropped(address(this), pokeData);

        uint[] memory feedIndexes = new uint[](1);
        feedIndexes[0] = 1;

        opScribe.drop(feedIndexes);
    }

    function test_setBar_IsAfterAuthedActionProtected() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        _setUpFeedsAndOpPokeOnce(pokeData);

        vm.expectEmit();
        emit OpPokeDataDropped(address(this), pokeData);

        opScribe.setBar(1);
    }

    //--------------------------------------------------------------------------
    // Private Helpers

    function _setUpFeedsAndOpPokeOnce(IScribe.PokeData memory pokeData)
        private
    {
        LibFeed.Feed[] memory feeds = _createAndLiftFeeds(opScribe.bar());

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribeOptimistic(address(opScribe)).opPoke(
            pokeData,
            schnorrData,
            feeds[0].signECDSA(
                opScribe.constructOpPokeMessage(pokeData, schnorrData)
            )
        );
    }
}
