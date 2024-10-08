// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeTest} from "./IScribeTest.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

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
        address indexed caller,
        IScribe.SchnorrData schnorrData,
        bytes schnorrErr
    );
    event OpPokeChallengedUnsuccessfully(
        address indexed caller, IScribe.SchnorrData schnorrData
    );
    event OpChallengeRewardPaid(
        address indexed challenger, IScribe.SchnorrData schnorrData, uint reward
    );
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

    function setUp(address scribe_) internal virtual override(IScribeTest) {
        super.setUp(scribe_);

        opScribe = IScribeOptimistic(scribe_);
    }

    // Necessary to receive opChallenge rewards.
    receive() external payable {}

    // -- Test: Deployment --

    function test_Deployment() public override(IScribeTest) {
        super.test_Deployment();

        // opFeedId set to zero.
        assertEq(opScribe.opFeedId(), 0);

        // OpChallengePeriod is non-zero.
        assertNotEq(opScribe.opChallengePeriod(), 0);

        // MaxChallengeRewards set to type(uint).max.
        assertEq(opScribe.maxChallengeReward(), type(uint).max);
    }

    // -- Test: Poke --

    function testFuzz_poke_FailsIf_AgeIsStale_DueTo_FinalizedOpPoke() public {
        uint val;
        uint age;

        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        // Execute opPoke.
        IScribe.PokeData memory opPokeData;
        opPokeData.val = uint128(1);
        opPokeData.age = uint32(block.timestamp);
        IScribe.SchnorrData memory schnorrData =
            feeds.signSchnorr(opScribe.constructPokeMessage(opPokeData));
        IScribe.ECDSAData memory ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(opPokeData, schnorrData)
        );
        opScribe.opPoke(opPokeData, schnorrData, ecdsaData);

        // Wait till challenge period over and opPoke finalized.
        vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

        // Verify opScribe's val is opPokeData's val.
        (val, age) = opScribe.readWithAge();
        assertEq(val, 1);
        assertEq(age, block.timestamp - opScribe.opChallengePeriod() - 1);

        // Prepare poke with older timestamp.
        IScribe.PokeData memory pokeData;
        pokeData.val = uint128(1e18);
        pokeData.age = uint32(1);
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        // Poke fails due to stale message.
        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.StaleMessage.selector,
                pokeData.age,
                block.timestamp - opScribe.opChallengePeriod() - 1
            )
        );
        opScribe.poke(pokeData, schnorrData);
    }

    // -- Test: opPoke --

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

        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.SchnorrData memory schnorrData;
        IScribe.ECDSAData memory ecdsaData;
        uint feedIndex;
        for (uint i; i < pokeDatas.length; i++) {
            // Select random feed signing opPoke.
            feedIndex = _bound(feedIndexSeeds[i], 0, feeds.length - 1);

            // Make sure val is non-zero and age not stale.
            pokeDatas[i].val =
                uint128(_bound(pokeDatas[i].val, 1, type(uint128).max));

            // @todo Weird behaviour if compiled via --via-ir.
            //       See comment in testFuzz_opPoke_FailsIf_AgeIsStale().
            //pokeDatas[i].age = uint32(block.timestamp);
            pokeDatas[i].age =
                uint32(1680220800 + (i * opScribe.opChallengePeriod()));

            // Schnorr multi-sign pokeData with feeds.
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeDatas[i]));

            // ECDSA single-sign (pokeData, schnorrData).
            ecdsaData = feeds[feedIndex].signECDSA(
                opScribe.constructOpPokeMessage(pokeDatas[i], schnorrData)
            );

            vm.expectEmit();
            emit OpPoked(
                address(this),
                feeds[feedIndex].pubKey.toAddress(),
                schnorrData,
                pokeDatas[i]
            );

            // Execute opPoke.
            opScribe.opPoke(pokeDatas[i], schnorrData, ecdsaData);

            uint wantAge = block.timestamp;
            // Note to use variable before warp as --via-ir optimization may
            // optimize it away. solc doesn't know about vm.warp().
            wantAge++;
            wantAge--;

            // Wait until challenge period over and opPokeData finalizes.
            vm.warp(block.timestamp + opScribe.opChallengePeriod());

            // Check that value can be read.
            _checkReadFunctions(pokeDatas[i].val, wantAge);
        }
    }

    function testFuzz_opPoke_FailsIf_AgeIsStale(
        IScribe.PokeData memory pokeData
    ) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        vm.assume(pokeData.val != 0);
        // Let pokeData's age ∊ [1, block.timestamp].
        pokeData.age = uint32(_bound(pokeData.age, 1, block.timestamp));

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // opPoke's age is set to block.timestamp.
        uint lastAge = uint32(block.timestamp);
        console2.log("lastAge", lastAge);

        // Set pokeData's age ∊ [0, block.timestamp].
        pokeData.age = uint32(_bound(pokeData.age, 0, block.timestamp));

        // Wait until opPokeData finalized.
        vm.warp(block.timestamp + opScribe.opChallengePeriod());

        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // @todo Possible bug in solc's --via-ir pipeline?
        //       The following hardcoded value is the block.timestamp before the
        //       warp a few lines above. Verifiable via the console2.log
        //       statement printing `lastAge`. However, if using the variable
        //       `lastAge` in the next statement it has a different value than
        //       being logged. This does not happen if compiled without --via-ir.
        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.StaleMessage.selector,
                pokeData.age,
                1680220800 /*lastAge*/
            )
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opPoke_FailsIf_AgeIsInTheFuture(
        IScribe.PokeData memory pokeData
    ) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        vm.assume(pokeData.val != 0);
        // Let pokeData's age ∊ [block.timestamp+1, type(uint32).max].
        pokeData.age =
            uint32(_bound(pokeData.age, block.timestamp + 1, type(uint32).max));

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute opPoke.
        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.FutureMessage.selector,
                pokeData.age,
                uint32(block.timestamp)
            )
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opPoke_FailsIf_ECDSASignatureInvalid(
        bool vSeed,
        uint rMask,
        uint sMask
    ) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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
            abi.encodeWithSelector(
                IScribeOptimistic.SignerNotFeed.selector, recovered
            )
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opPoke_FailsIf_opPokeDataInChallengePeriodExists(
        uint warpSeed
    ) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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

    // See audits/Cantina@v2.0.0.pdf.
    function testFuzz_opPoke_FailsIf_BarNotReached_DueTo_GasAttack(
        uint feedIdsLengthSeed
    ) public {
        // Note to stay reasonable with calldata load.
        uint feedIdsLength =
            _bound(feedIdsLengthSeed, uint(type(uint8).max) + 1, 1_000);

        _liftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;

        IScribe.SchnorrData memory schnorrData;
        for (uint i; i < feedIdsLength; i++) {
            schnorrData.feedIds =
                abi.encodePacked(schnorrData.feedIds, uint8(0xFF));
        }

        IScribe.ECDSAData memory ecdsaData;

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.BarNotReached.selector, type(uint8).max, opScribe.bar()
            )
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    // -- Test: opChallenge --

    function testFuzz_opChallenge_opPokeDataValidAndNotStale(uint warpSeed)
        public
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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

        // Wait for some non-zero time less than opChallengePeriod.
        vm.warp(
            block.timestamp
                + bound(warpSeed, 1, opScribe.opChallengePeriod() - 1)
        );

        uint balanceBefore = address(this).balance;

        vm.expectEmit();
        emit OpPokeChallengedUnsuccessfully(address(this), schnorrData);

        // Challenge opPoke.
        bool opPokeInvalid = opScribe.opChallenge(schnorrData);

        // opPoke not invalid.
        assertFalse(opPokeInvalid);

        // No reward paid.
        assertEq(address(this).balance, balanceBefore);

        // opPokeData finalized.
        assertEq(opScribe.read(), pokeData.val);

        // Possible to directly opPoke again.
        pokeData.age = uint32(block.timestamp);
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);
    }

    function testFuzz_opChallenge_opPokeDataValidButStale(uint warpSeed)
        public
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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

        vm.expectEmit();
        emit OpPokeChallengedUnsuccessfully(address(this), schnorrData);

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

        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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

        {
            // Expect events.
            vm.expectEmit();
            emit OpChallengeRewardPaid(address(this), schnorrData, 1 ether);

            vm.expectEmit();
            emit OpPokeChallengedSuccessfully(
                address(this),
                schnorrData,
                abi.encodeWithSelector(IScribe.SchnorrSignatureInvalid.selector)
            );
        }

        // Challenge opPoke.
        bool opPokeInvalid = opScribe.opChallenge(schnorrData);

        // opPoke invalid.
        assertTrue(opPokeInvalid);

        // opFeed dropped.
        bool isFeed = opScribe.feeds(feeds[0].pubKey.toAddress());
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
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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

    function test_opChallenge_FailsIf_CalledSubsequently() public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

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

        bool opPokeInvalid = opScribe.opChallenge(schnorrData);
        assertFalse(opPokeInvalid);

        vm.expectRevert(IScribeOptimistic.NoOpPokeToChallenge.selector);
        opScribe.opChallenge(schnorrData);
    }

    // See audits/Cantina@v2.0.0.pdf.
    function test_opChallenge_CalldataEncodingAttack() public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 1;
        assertEq(opScribe.feeds().length, 2, "expected 2 feeds to start with");

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(pokeData, schnorrData)
        );

        // Execute valid opPoke.
        opScribe.opPoke(pokeData, schnorrData, ecdsaData);

        // Challenge opPoke.
        // bytes memory defaultCalldata = abi.encodeCall(opScribe.opChallenge, schnorrData);
        // console2.logBytes(defaultCalldata);
        // 8928a1f8 // selector
        // 0000000000000000000000000000000000000000000000000000000000000020 // struct offset
        // fecd661c0731ca99672edb7303a072da3c2b8342e714c2f2a90639b966298958 // signature
        // 000000000000000000000000026428bf84a659a2d371be1e705613d89d93f78f // commitment
        // 0000000000000000000000000000000000000000000000000000000000000060 // offset(feedIds)
        // 0000000000000000000000000000000000000000000000000000000000000002 // length(feedIds)
        // 2b68000000000000000000000000000000000000000000000000000000000000 // feedIds
        bytes memory customCalldata = (
            hex"8928a1f8" // selector
            hex"0000000000000000000000000000000000000000000000000000000000000020" // struct offset
            hex"fecd661c0731ca99672edb7303a072da3c2b8342e714c2f2a90639b966298958" // signature
            hex"000000000000000000000000026428bf84a659a2d371be1e705613d89d93f78f" // commitment
            hex"00000000000000000000000000000000000000000000000000000000000000a0" // offset(feedIds)
            hex"0000000000000000000000000000000000000000000000000000000000000002" // injected(feedIds).length
            hex"2b2b000000000000000000000000000000000000000000000000000000000000" // injected(feedIds) (double sign)
            hex"0000000000000000000000000000000000000000000000000000000000000002" // length(feedIds)
            hex"2b68000000000000000000000000000000000000000000000000000000000000"
        ); // feedIds

        (bool success, bytes memory retData) =
            address(opScribe).call(customCalldata);
        if (!success || retData.length != 32) revert();
        bool opPokeInvalid = abi.decode(retData, (bool));

        // Original PoC:
        // assertTrue(opPokeInvalid, "expected opChallenge to return true");
        // assertEq(opScribe.feeds().length, 1, "expected feed to be dropped");

        // Fixed:
        assertFalse(opPokeInvalid, "opChallenge: Calldata encoding attack");
        assertEq(
            opScribe.feeds().length, 2, "opChallenge: Calldata encoding attack"
        );
    }

    // -- Test: Public View Functions --

    function testFuzz_challengeReward(uint maxChallengeReward, uint balance)
        public
    {
        opScribe.setMaxChallengeReward(maxChallengeReward);
        vm.deal(address(opScribe), balance);

        uint want = balance > maxChallengeReward ? maxChallengeReward : balance;
        uint got = opScribe.challengeReward();
        assertEq(got, want);
    }

    // -- Test: Auth Protected Functions --

    function testFuzz_setMaxChallengeReward(uint maxChallengeReward) public {
        // Only expect event if maxChallengeReward actually changes.
        if (maxChallengeReward != opScribe.maxChallengeReward()) {
            vm.expectEmit();
            emit MaxChallengeRewardUpdated(
                address(this), opScribe.maxChallengeReward(), maxChallengeReward
            );
        }

        opScribe.setMaxChallengeReward(maxChallengeReward);

        assertEq(opScribe.maxChallengeReward(), maxChallengeReward);
    }

    function test_setMaxChallengeReward_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        opScribe.setMaxChallengeReward(0);
    }

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

    function test_setOpChallengePeriod_DropsFinalizedOpPoke_If_NonFinalizedAfterUpdate(
    ) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        // Execute opPoke.
        IScribe.PokeData memory opPokeData;
        opPokeData.val = uint128(1);
        opPokeData.age = uint32(block.timestamp);
        IScribe.SchnorrData memory schnorrData =
            feeds.signSchnorr(opScribe.constructPokeMessage(opPokeData));
        IScribe.ECDSAData memory ecdsaData = feeds[0].signECDSA(
            opScribe.constructOpPokeMessage(opPokeData, schnorrData)
        );
        opScribe.opPoke(opPokeData, schnorrData, ecdsaData);

        // Wait till challenge period over and opPoke finalized.
        vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

        // Update opPokeData's age to timestamp set by opScribe.
        opPokeData.age =
            uint32(block.timestamp - opScribe.opChallengePeriod() - 1);

        // Verify opScribe's val is opPokeData's val.
        (uint val, uint age) = opScribe.readWithAge();
        assertEq(val, 1);
        assertEq(age, opPokeData.age);

        // Increase opChallengePeriod to un-finalize opPoke again.
        // Expect opPoke to be dropped.
        vm.expectEmit();
        emit OpPokeDataDropped(address(this), opPokeData);
        opScribe.setOpChallengePeriod(type(uint16).max);

        // Reading opScribe fails as no val set.
        (bool ok,) = opScribe.tryRead();
        assertFalse(ok);
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

    // - Test: Auth Protected Functions Are _afterAuthedAction Protected -

    function _setUpFeedsAndOpPokeOnce(IScribe.PokeData memory pokeData)
        private
        returns (LibFeed.Feed[] memory)
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));

        opScribe.opPoke(
            pokeData,
            schnorrData,
            feeds[0].signECDSA(
                opScribe.constructOpPokeMessage(pokeData, schnorrData)
            )
        );

        return feeds;
    }

    function testFuzz_setOpChallengePeriod_IsAfterAuthedActionProtected(
        bool opPokeFinalized
    ) public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        _setUpFeedsAndOpPokeOnce(pokeData);

        if (opPokeFinalized) {
            vm.warp(block.timestamp + opScribe.opChallengePeriod());
        } else {
            vm.expectEmit();
            emit OpPokeDataDropped(address(this), pokeData);
        }

        opScribe.setOpChallengePeriod(1);
    }

    function testFuzz_drop_Single_IsAfterAuthedActionProtected(
        bool opPokeFinalized
    ) public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        LibFeed.Feed[] memory feeds = _setUpFeedsAndOpPokeOnce(pokeData);

        if (opPokeFinalized) {
            vm.warp(block.timestamp + opScribe.opChallengePeriod());
        } else {
            vm.expectEmit();
            emit OpPokeDataDropped(address(this), pokeData);
        }

        opScribe.drop(feeds[0].id);
    }

    function testFuzz_drop_Multiple_IsAfterAuthedActionProtected(
        bool opPokeFinalized
    ) public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        LibFeed.Feed[] memory feeds = _setUpFeedsAndOpPokeOnce(pokeData);

        if (opPokeFinalized) {
            vm.warp(block.timestamp + opScribe.opChallengePeriod());
        } else {
            vm.expectEmit();
            emit OpPokeDataDropped(address(this), pokeData);
        }

        uint8[] memory feedIds = new uint8[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            feedIds[i] = feeds[i].id;
        }

        opScribe.drop(feedIds);
    }

    function testFuzz_setBar_IsAfterAuthedActionProtected(bool opPokeFinalized)
        public
    {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        _setUpFeedsAndOpPokeOnce(pokeData);

        if (opPokeFinalized) {
            vm.warp(block.timestamp + opScribe.opChallengePeriod());
        } else {
            vm.expectEmit();
            emit OpPokeDataDropped(address(this), pokeData);
        }

        opScribe.setBar(1);
    }

    // -- Test: _afterAuthedAction Behaviour --

    /// @dev Proves that an _afterAuthedAction executed after 2 {poke,opPoke}'s
    ///      executed does not leave opScribe without a value.
    ///
    ///      Possibilities for 2 {poke,opPoke}'s:
    ///      0: poke()                 + poke()                 -> val is second poke()'s val
    ///      1: poke()                 + non-finalized opPoke() -> val is poke()'s val
    ///      2: poke()                 + finalized opPoke()     -> val is finalized opPoke()'s val
    ///      3: finalized opPoke()     + non-finalized opPoke() -> val is finalized opPoke()'s val
    ///      4: finalized opPoke()     + poke()                 -> val is poke()'s val
    ///      5: finalized opPoke()     + finalized opPoke()     -> val is second finalized opPoke()'s val
    ///      6: non-finalized opPoke() + poke()                 -> val is poke()'s val
    function testFuzz_afterAuthedAction_ProvidesValue_If_MoreThanOncePoked(
        uint pathSeed
    ) public {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        uint path = _bound(pathSeed, 0, 6);

        uint128 otherVal = 1;
        uint128 wantVal = 2;

        IScribe.PokeData memory pokeData;
        IScribe.SchnorrData memory schnorrData;

        if (path == 0) {
            // 1. poke()
            pokeData.val = otherVal;
            pokeData.age = 1;
            opScribe.poke(
                pokeData,
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
            );

            vm.warp(block.timestamp + 1);

            // 2. poke()
            pokeData.val = wantVal;
            pokeData.age = uint32(block.timestamp);
            opScribe.poke(
                pokeData,
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
            );

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }

        if (path == 1) {
            // 1. poke()
            pokeData.val = wantVal;
            pokeData.age = 1;
            opScribe.poke(
                pokeData,
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
            );

            vm.warp(block.timestamp + 1);

            // 2. non-finalized opPoke()
            pokeData.val = otherVal;
            pokeData.age = uint32(block.timestamp);
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }

        if (path == 2) {
            // 1. poke()
            pokeData.val = otherVal;
            pokeData.age = 1;
            opScribe.poke(
                pokeData,
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
            );

            vm.warp(block.timestamp + 1);

            // 2. finalized opPoke()
            pokeData.val = wantVal;
            pokeData.age = uint32(block.timestamp);
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Finalize opPoke().
            vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }

        if (path == 3) {
            // 1. finalized opPoke()
            pokeData.val = wantVal;
            pokeData.age = 1;
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Finalize opPoke().
            vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

            // 2. non-finalized opPoke()
            pokeData.val = otherVal;
            pokeData.age = uint32(block.timestamp);
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }

        if (path == 4) {
            // 1. finalized opPoke()
            pokeData.val = otherVal;
            pokeData.age = 1;
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Finalize opPoke().
            vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

            // 2. poke()
            pokeData.val = wantVal;
            pokeData.age = uint32(block.timestamp);
            opScribe.poke(
                pokeData,
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
            );

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }

        if (path == 5) {
            // 1. finalized opPoke()
            pokeData.val = otherVal;
            pokeData.age = 1;
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Finalize opPoke()
            vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

            // 2. finalized opPoke()
            pokeData.val = wantVal;
            pokeData.age = uint32(block.timestamp);
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            // Finalize opPoke().
            vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }

        if (path == 6) {
            // 1. non-finalized opPoke()
            pokeData.val = otherVal;
            pokeData.age = 1;
            schnorrData =
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData));
            opScribe.opPoke(
                pokeData,
                schnorrData,
                feeds[0].signECDSA(
                    opScribe.constructOpPokeMessage(pokeData, schnorrData)
                )
            );

            vm.warp(block.timestamp + 1);

            // 2. poke()
            pokeData.val = wantVal;
            pokeData.age = uint32(block.timestamp);
            opScribe.poke(
                pokeData,
                feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
            );

            // Execute _afterAuthedAction
            opScribe.setBar(3);

            assertEq(opScribe.read(), wantVal);
        }
    }

    // -----------------------
    // 1. Case:
    //
    // State:
    //    _pokeData    = NULL
    //    _opPokeData  = Non-Finalized
    //
    // => value = NULL
    // => age   = NULL

    function _setUp_afterAuthedAction_1()
        internal
        returns (
            IScribe.PokeData memory,
            IScribe.PokeData memory,
            LibFeed.Feed[] memory
        )
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData;
        IScribe.PokeData memory opPokeData = IScribe.PokeData(1, 1);
        IScribe.SchnorrData memory schnorrData =
            feeds.signSchnorr(opScribe.constructPokeMessage(opPokeData));

        opScribe.opPoke(
            opPokeData,
            schnorrData,
            feeds[0].signECDSA(
                opScribe.constructOpPokeMessage(opPokeData, schnorrData)
            )
        );

        return (pokeData, opPokeData, feeds);
    }

    function test_afterAuthedAction_1_setBar() public {
        _setUp_afterAuthedAction_1();

        opScribe.setBar(3);

        (bool ok,) = opScribe.tryRead();
        assertFalse(ok);
        console2.log(
            "afterAuthedAction: {_pokeData=NULL, _opPokeData=Non-Finalized} + setBar() => {value=NULL, age = NULL}"
        );
    }

    function test_afterAuthedAction_1_drop() public {
        (,, LibFeed.Feed[] memory feeds) = _setUp_afterAuthedAction_1();

        opScribe.drop(feeds[0].id);

        (bool ok,) = opScribe.tryRead();
        assertFalse(ok);
        console2.log(
            "afterAuthedAction: {_pokeData=NULL, _opPokeData=Non-Finalized} + drop() => {value=NULL, age=NULL}"
        );
    }

    function test_afterAuthedAction_1_setChallengePeriod() public {
        _setUp_afterAuthedAction_1();

        // Note that _opPokeData still non-finalized after challenge period
        // update.
        opScribe.setOpChallengePeriod(1);

        (bool ok,) = opScribe.tryRead();
        assertFalse(ok);
        console2.log(
            "afterAuthedAction: {_pokeData=NULL, _opPokeData=Non-Finalized} + setOpChallengePeriod() => {value=NULL, age=NULL}"
        );
    }

    // -----------------------
    // 2. Case:
    //
    // State:
    //    _pokeData    = Non-NULL
    //    _opPokeData  = Non-Finalized
    //
    // => value = _pokeData
    // => age   = block.timestamp

    function _setUp_afterAuthedAction_2()
        internal
        returns (
            IScribe.PokeData memory,
            IScribe.PokeData memory,
            LibFeed.Feed[] memory
        )
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData = IScribe.PokeData(2, 1);
        opScribe.poke(
            pokeData, feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
        );

        vm.warp(block.timestamp + 1);

        IScribe.PokeData memory opPokeData =
            IScribe.PokeData(1, uint32(block.timestamp));
        IScribe.SchnorrData memory schnorrData =
            feeds.signSchnorr(opScribe.constructPokeMessage(opPokeData));

        opScribe.opPoke(
            opPokeData,
            schnorrData,
            feeds[0].signECDSA(
                opScribe.constructOpPokeMessage(opPokeData, schnorrData)
            )
        );

        return (pokeData, opPokeData, feeds);
    }

    function test_afterAuthedAction_2_setBar() public {
        (IScribe.PokeData memory pokeData,,) = _setUp_afterAuthedAction_2();

        opScribe.setBar(3);

        (bool ok, uint val, uint age) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, pokeData.val);
        assertEq(age, block.timestamp);
        console2.log(
            "afterAuthedAction: {_pokeData=Non-NULL, _opPokeData=Non-Finalized} + setBar() => {value=_pokeData, age=block.timestamp}"
        );
    }

    function test_afterAuthedAction_2_drop() public {
        (IScribe.PokeData memory pokeData,, LibFeed.Feed[] memory feeds) =
            _setUp_afterAuthedAction_2();

        opScribe.drop(feeds[0].id);

        (bool ok, uint val, uint age) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, pokeData.val);
        assertEq(age, block.timestamp);
        console2.log(
            "afterAuthedAction: {_pokeData=Non-NULL, _opPokeData=Non-Finalized} + drop() => {value=_pokeData, age=block.timestamp}"
        );
    }

    function test_afterAuthedAction_2_setChallengePeriod() public {
        (IScribe.PokeData memory pokeData,,) = _setUp_afterAuthedAction_2();

        // Note that _opPokeData still non-finalized after challenge period
        // update.
        opScribe.setOpChallengePeriod(1);

        (bool ok, uint val, uint age) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, pokeData.val);
        assertEq(age, block.timestamp);
        console2.log(
            "afterAuthedAction: {_pokeData=Non-NULL, _opPokeData=Non-Finalized} + setOpChallengePeriod() => {value=_pokeData, age=block.timestamp}"
        );
    }

    // -----------------------
    // 3. Case:
    //
    // State:
    //    _pokeData    = NULL
    //    _opPokeData  = Finalized
    //
    // => value = _opPokeData
    // => age   = block.timestamp

    function _setUp_afterAuthedAction_3()
        internal
        returns (
            IScribe.PokeData memory,
            IScribe.PokeData memory,
            LibFeed.Feed[] memory
        )
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.PokeData memory opPokeData =
            IScribe.PokeData(1, uint32(block.timestamp));
        IScribe.SchnorrData memory schnorrData =
            feeds.signSchnorr(opScribe.constructPokeMessage(opPokeData));

        opScribe.opPoke(
            opPokeData,
            schnorrData,
            feeds[0].signECDSA(
                opScribe.constructOpPokeMessage(opPokeData, schnorrData)
            )
        );

        vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

        return (IScribe.PokeData(0, 0), opPokeData, feeds);
    }

    function test_afterAuthedAction_3_setBar() public {
        (, IScribe.PokeData memory opPokeData,) = _setUp_afterAuthedAction_3();

        opScribe.setBar(3);

        (bool ok, uint val, uint age) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, opPokeData.val);
        assertEq(age, uint32(block.timestamp));
        console2.log(
            "afterAuthedAction: {_pokeData=NULL, _opPokeData=Finalized} + setBar() => {value=opPokeData, age=block.timestamp}"
        );
    }

    function test_afterAuthedAction_3_drop() public {
        (, IScribe.PokeData memory opPokeData, LibFeed.Feed[] memory feeds) =
            _setUp_afterAuthedAction_3();

        opScribe.drop(feeds[0].id);

        (bool ok, uint val, uint age) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, opPokeData.val);
        assertEq(age, uint32(block.timestamp));
        console2.log(
            "afterAuthedAction: {_pokeData=NULL, _opPokeData=Finalized} + drop() => {value=opPokeData, age=block.timestamp}"
        );
    }

    function test_afterAuthedAction_3_setChallengePeriod() public {
        (, IScribe.PokeData memory opPokeData,) = _setUp_afterAuthedAction_3();

        // Update challenge period so that _opPokeData still finalized.
        opScribe.setOpChallengePeriod(1);

        (bool ok, uint val, uint age) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, opPokeData.val);
        assertEq(age, uint32(block.timestamp));
        console2.log(
            "afterAuthedAction: {_pokeData=NULL, _opPokeData=Finalized} + setOpChallengePeriod() => {value=opPokeData, age=block.timestamp}"
        );
    }

    // -----------------------
    // 4. Case:
    //
    // State:
    //    _pokeData    = Non-NULL
    //    _opPokeData  = Finalized
    //
    // => value = _opPokeData
    // => age   = block.timestamp

    function _setUp_afterAuthedAction_4()
        internal
        returns (
            IScribe.PokeData memory,
            IScribe.PokeData memory,
            LibFeed.Feed[] memory
        )
    {
        LibFeed.Feed[] memory feeds = _liftFeeds(opScribe.bar());

        IScribe.PokeData memory pokeData = IScribe.PokeData(2, 1);
        opScribe.poke(
            pokeData, feeds.signSchnorr(opScribe.constructPokeMessage(pokeData))
        );

        vm.warp(block.timestamp + 1);

        IScribe.PokeData memory opPokeData =
            IScribe.PokeData(1, uint32(block.timestamp));
        IScribe.SchnorrData memory schnorrData =
            feeds.signSchnorr(opScribe.constructPokeMessage(opPokeData));

        opScribe.opPoke(
            opPokeData,
            schnorrData,
            feeds[0].signECDSA(
                opScribe.constructOpPokeMessage(opPokeData, schnorrData)
            )
        );

        vm.warp(block.timestamp + opScribe.opChallengePeriod() + 1);

        return (pokeData, opPokeData, feeds);
    }

    function test_afterAuthedAction_4_setBar() public {
        (, IScribe.PokeData memory opPokeData,) = _setUp_afterAuthedAction_4();

        opScribe.setBar(3);

        (bool ok, uint val,) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, opPokeData.val);
        console2.log(
            "afterAuthedAction: {_pokeData=Non-NULL, _opPokeData=Finalized} + setBar() => {value=_opPokeData, age=block.timestamp}"
        );
    }

    function test_afterAuthedAction_4_drop() public {
        (, IScribe.PokeData memory opPokeData, LibFeed.Feed[] memory feeds) =
            _setUp_afterAuthedAction_4();

        opScribe.drop(feeds[0].id);

        (bool ok, uint val,) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, opPokeData.val);
        console2.log(
            "afterAuthedAction: {_pokeData=Non-NULL, _opPokeData=Finalized} + drop() => {value=_opPokeData, age=block.timestamp}"
        );
    }

    function test_afterAuthedAction_4_setChallengePeriod() public {
        (, IScribe.PokeData memory opPokeData,) = _setUp_afterAuthedAction_4();

        // Update challenge period so that _opPokeData still finalized.
        opScribe.setOpChallengePeriod(1);

        (bool ok, uint val,) = opScribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, opPokeData.val);
        console2.log(
            "afterAuthedAction: {_pokeData=Non-NULL, _opPokeData=Finalized} + setOpChallengePeriod() => {value=_opPokeData, age=block.timestamp}"
        );
    }
}
