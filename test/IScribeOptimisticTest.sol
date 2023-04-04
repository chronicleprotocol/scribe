pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeTest} from "./IScribeTest.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

/**
 * @notice Provides IScribeOptimistic Unit Tests
 */
abstract contract IScribeOptimisticTest is IScribeTest {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeOptimistic opScribe;

    // Events copied from IScribeOptimistic.
    // @todo Add missing events + test for emission.
    event OpPokeDataDropped(address indexed caller, uint128 val, uint32 age);
    event OpChallengePeriodUpdated(
        address indexed caller,
        uint16 oldOpChallengePeriod,
        uint16 newOpChallengePeriod
    );

    function setUp(address scribe_) internal override(IScribeTest) {
        super.setUp(scribe_);

        opScribe = IScribeOptimistic(scribe_);
    }

    /*//////////////////////////////////////////////////////////////
                            TEST: DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public override(IScribeTest) {
        super.test_deployment();

        // opFeed and opCommitment not set.
        assertEq(opScribe.opFeed(), address(0));
        assertEq(opScribe.opCommitment(), bytes32(0));

        // OpChallengePeriod is set to 1 hour.
        assertEq(opScribe.opChallengePeriod(), 1 hours);
    }

    /*//////////////////////////////////////////////////////////////
                         TEST: OP POKE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_opPoke_Initial(IScribe.PokeData memory pokeData) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);

        assertEq(opScribe.opFeed(), feeds[0].pubKey.toAddress());
        assertEq(
            opScribe.opCommitment(),
            LibHelpers.constructOpCommitment(
                pokeData, schnorrSignatureData, WAT
            )
        );

        // Wait until challenge period over and opPokeData finalizes.
        _warpToEndOfOpChallengePeriod();

        assertEq(opScribe.read(), pokeData.val);
        (uint val, bool ok) = opScribe.peek();
        assertEq(val, pokeData.val);
        assertTrue(ok);

        // Note that the opFeed & opCommitment is not deleted after finalization.
        assertEq(opScribe.opFeed(), feeds[0].pubKey.toAddress());
        assertEq(
            opScribe.opCommitment(),
            LibHelpers.constructOpCommitment(
                pokeData, schnorrSignatureData, WAT
            )
        );
    }

    function test_opPoke_Initial_FailsIf_AgeIsZero() public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = 0;

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        vm.expectRevert(
            abi.encodeWithSelector(IScribe.StaleMessage.selector, 0, 0)
        );
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function test_opPoke_Continuously(IScribe.PokeData[] memory pokeDatas)
        public
    {
        // Ensure pokeDatas' val is never zero.
        for (uint i; i < pokeDatas.length; i++) {
            vm.assume(pokeDatas[i].val != 0);
        }

        for (uint i; i < pokeDatas.length; i++) {
            pokeDatas[i].age = uint32(
                bound(
                    pokeDatas[i].age,
                    block.timestamp + 1,
                    block.timestamp + 1 weeks
                )
            );

            IScribe.SchnorrSignatureData memory schnorrSignatureData =
                LibHelpers.makeSchnorrSignature(feeds, pokeDatas[i], WAT);

            // forgefmt: disable-next-item
            IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
                LibHelpers.makeECDSASignature(
                    i % 2 == 0 ? feeds[0] : feeds[1],
                    pokeDatas[i],
                    schnorrSignatureData,
                    WAT
                );

            opScribe.opPoke(
                pokeDatas[i], schnorrSignatureData, ecdsaSignatureData
            );

            assertEq(
                opScribe.opFeed(),
                (i % 2 == 0 ? feeds[0] : feeds[1]).pubKey.toAddress()
            );
            assertEq(
                opScribe.opCommitment(),
                LibHelpers.constructOpCommitment(
                    pokeDatas[i], schnorrSignatureData, WAT
                )
            );

            // Wait until challenge period over and opPokeData finalizes.
            _warpToEndOfOpChallengePeriod();

            assertEq(opScribe.read(), pokeDatas[i].val);
            (uint val, bool ok) = opScribe.peek();
            assertEq(val, pokeDatas[i].val);
            assertTrue(ok);
        }
    }

    function testFuzz_opPoke_FailsIf_PokeData_IsStale(
        IScribe.PokeData memory pokeData
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        // Poke once.
        opScribe.poke(
            pokeData, LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT)
        );

        // Last poke's age is set to block.timestamp.
        uint currentAge = uint32(block.timestamp);

        // New pokeData's age ∊ [0, block.timestamp].
        pokeData.age = uint32(bound(pokeData.age, 0, block.timestamp));

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribe.StaleMessage.selector, pokeData.age, currentAge
            )
        );
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function testFuzz_opPoke_DoesNotFailIf_SchnorrSignatureData_HasInsufficientNumberOfSigners(
        IScribe.PokeData memory pokeData,
        uint numberSignersSeed
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = opScribe.bar();
        uint numberSigners = bound(numberSignersSeed, 0, bar - 1);

        // Create set of feeds with less than bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](numberSigners);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        // Does not fail.
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function testFuzz_opPoke_DoesNotFailIf_SchnorrSignatureData_HasNonOrderedSigners(
        IScribe.PokeData memory pokeData,
        uint duplicateIndexSeed
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = opScribe.bar();

        // Create set of feeds with bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](bar);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        // But have the first feed two times in the set.
        uint index = bound(duplicateIndexSeed, 1, feeds_.length - 1);
        feeds_[index] = feeds_[0];

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        // Does not fail.
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function test_opPoke_DoesNotFailIf_SchnorrSignatureData_HasNonFeedAsSigner()
        public
    {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        // Add non-feed to feeds.
        feeds.push(notFeed);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        // Does not fail.
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function testFuzz_opPoke_DoesNotFailsIf_SchnorrSignatureData_FailsSignatureVerification(
        IScribe.PokeData memory pokeData,
        uint signatureMask,
        uint160 commitmentMask
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // "Randomly" mutate schnorrSignatureData.
        schnorrSignatureData.signature =
            bytes32(uint(schnorrSignatureData.signature) ^ signatureMask);
        schnorrSignatureData.commitment =
            address(uint160(schnorrSignatureData.commitment) ^ commitmentMask);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        // Does not fail.
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function testFuzz_opPoke_FailsIf_ECDSASignatureData_FailsSignatureVerification(
        IScribe.PokeData memory pokeData,
        uint8 vMask,
        uint rMask,
        uint sMask
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        // "Randomly" mutate ecdsaSignatureData.
        // Note at most only set v's last bit.
        ecdsaSignatureData.v = (ecdsaSignatureData.v ^ vMask) & 0x1;
        ecdsaSignatureData.r = bytes32(uint(ecdsaSignatureData.r) ^ rMask);
        ecdsaSignatureData.s = bytes32(uint(ecdsaSignatureData.s) ^ sMask);

        vm.expectRevert();
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    function test_Fuzz_opPoke_FailsIf_SomeOpPokeDataAlreadyInChallengePeriod(
        IScribe.PokeData memory pokeData,
        uint warpSeed
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);

        // Warp to some time before challenge period over.
        uint opChallengePeriod = opScribe.opChallengePeriod();
        vm.warp(block.timestamp + bound(warpSeed, 0, opChallengePeriod - 1));

        // Adjust pokeData's age to not run into "StaleMessage".
        pokeData.age = uint32(block.timestamp);

        schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        ecdsaSignatureData = LibHelpers.makeECDSASignature(
            feeds[0], pokeData, schnorrSignatureData, WAT
        );

        vm.expectRevert(IScribeOptimistic.InChallengePeriod.selector);
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
    }

    /*//////////////////////////////////////////////////////////////
                      TEST: OP CHALLENGE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_opChallenge_DoesNotKickOpFeedIf_SchnorrSignatureDataValid(
    ) public {}

    function testFuzz_opChallenge_FinalizesOpPokeDataIf_SchnorrSignatureValid()
        public
    {}

    function testFuzz_opChallenge_KicksOpFeedIf_SchnorrSignatureDataInvalid_DueTo_HasInsufficientNumberOfSigners(
        IScribe.PokeData memory pokeData,
        uint numberSignersSeed
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = opScribe.bar();
        uint numberSigners = bound(numberSignersSeed, 0, bar - 1);

        // Create set of feeds with less than bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](numberSigners);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        // Use less than bar signers for Schnorr signature.
        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds_, pokeData, WAT);

        // Cache opFeed.
        LibHelpers.Feed memory opFeed = feeds[0];

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                opFeed,
                pokeData,
                schnorrSignatureData,
                WAT
            );

        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);

        opScribe.opChallenge(pokeData, schnorrSignatureData);

        // opFeed kicked.
        assertFalse(opScribe.feeds(opFeed.pubKey.toAddress()));
        // opPokeData not finalized.
        (uint val, bool ok) = opScribe.peek();
        assertFalse(ok);
    }

    function testFuzz_opChallenge_KicksOpFeedIf_SchnorrSignatureDataInvalid_DueTo_HasNonOrderedSigners(
        IScribe.PokeData memory pokeData,
        uint duplicateIndexSeed
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        uint bar = opScribe.bar();

        // Create set of feeds with bar feeds.
        LibHelpers.Feed[] memory feeds_ = new LibHelpers.Feed[](bar);
        for (uint i; i < feeds_.length; i++) {
            feeds_[i] = feeds[i];
        }

        // But have the first feed two times in the set.
        uint index = bound(duplicateIndexSeed, 1, feeds_.length - 1);
        feeds_[index] = feeds_[0];

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds_, pokeData, WAT);

        // Cache opFeed.
        LibHelpers.Feed memory opFeed = feeds[0];

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                opFeed,
                pokeData,
                schnorrSignatureData,
                WAT
            );

        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);

        opScribe.opChallenge(pokeData, schnorrSignatureData);

        // opFeed kicked.
        assertFalse(opScribe.feeds(opFeed.pubKey.toAddress()));
        // opPokeData not finalized.
        (uint val, bool ok) = opScribe.peek();
        assertFalse(ok);
    }

    function test_opChallenge_KicksOpFeedIf_SchnorrSignatureDataInvalid_DueTo_HasNonFeedAsSigner(
    ) public {
        IScribe.PokeData memory pokeData;
        pokeData.val = 1;
        pokeData.age = uint32(block.timestamp);

        // Add non-feed to feeds.
        feeds.push(notFeed);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // Cache opFeed.
        LibHelpers.Feed memory opFeed = feeds[0];

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                opFeed,
                pokeData,
                schnorrSignatureData,
                WAT
            );

        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);

        opScribe.opChallenge(pokeData, schnorrSignatureData);

        // opFeed kicked.
        assertFalse(opScribe.feeds(opFeed.pubKey.toAddress()));
        // opPokeData not finalized.
        (uint val, bool ok) = opScribe.peek();
        assertFalse(ok);
    }

    function testFuzz_opChallenge_KicksOpFeedIf_SchnorrSignatureDataInvalid_DueTo_FailsSignatureVerification(
    ) public {
        // @todo Implement once Schnorr signature verification enabled.
        console2.log("NOT IMPLEMENTED");
    }

    function testFuzz_opChallenge_FailsIf_NoPokeToChallenge_Because_NoPokeDataExists(
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrSignatureData memory schnorrSignatureData
    ) public {
        vm.expectRevert(IScribeOptimistic.NoOpPokeToChallenge.selector);
        opScribe.opChallenge(pokeData, schnorrSignatureData);
    }

    function testFuzz_opChallenge_FailsIf_NoPokeToChallenge_Because_PokeDataNotInChallengePeriod(
        IScribe.PokeData memory pokeData
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        // opPoke and warp to opPoke's challenge period over.
        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);
        _warpToEndOfOpChallengePeriod();

        vm.expectRevert(IScribeOptimistic.NoOpPokeToChallenge.selector);
        opScribe.opChallenge(pokeData, schnorrSignatureData);
    }

    function testFuzz_opChallenge_FailsIf_ArgumentsDoNotMatchCommitment(
        IScribe.PokeData memory pokeData
    ) public {
        vm.assume(pokeData.val != 0);
        vm.assume(pokeData.age != 0);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        opScribe.opPoke(pokeData, schnorrSignatureData, ecdsaSignatureData);

        // Change pokeData's val.
        pokeData.val--;

        bytes32 opCommitment = LibHelpers.constructOpCommitment(
            pokeData, schnorrSignatureData, WAT
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IScribeOptimistic.ArgumentsDoNotMatchOpCommitment.selector,
                opCommitment,
                opScribe.opCommitment()
            )
        );
        opScribe.opChallenge(pokeData, schnorrSignatureData);
    }

    /*//////////////////////////////////////////////////////////////
                     TEST: AUTH PROTECTED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_setOpChallengePeriod(uint16 opChallengePeriod) public {
        vm.assume(opChallengePeriod != 0);

        // Only expect event if opChallengePeriod actually changes.
        if (opChallengePeriod != opScribe.opChallengePeriod()) {
            vm.expectEmit(true, true, true, true);
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

    function test_setOpChallengePeriod_DropsOpPokeData() public {
        _setUpFeedsAndOpPokeOnce(1, uint32(block.timestamp));

        vm.expectEmit(true, true, true, true);
        emit OpPokeDataDropped(address(this), 1, uint32(block.timestamp));

        opScribe.setOpChallengePeriod(1);
    }

    function test_drop_Single_DropsOpPokeData() public {
        _setUpFeedsAndOpPokeOnce(1, uint32(block.timestamp));

        vm.expectEmit(true, true, true, true);
        emit OpPokeDataDropped(address(this), 1, uint32(block.timestamp));

        opScribe.drop(LibSecp256k1.Point(1, 1));
    }

    function test_drop_Multiple_DropsOpPokeData() public {
        _setUpFeedsAndOpPokeOnce(1, uint32(block.timestamp));

        vm.expectEmit(true, true, true, true);
        emit OpPokeDataDropped(address(this), 1, uint32(block.timestamp));

        opScribe.drop(new LibSecp256k1.Point[](0));
    }

    function test_setBar_DropsOpPokeData() public {
        _setUpFeedsAndOpPokeOnce(1, uint32(block.timestamp));

        vm.expectEmit(true, true, true, true);
        emit OpPokeDataDropped(address(this), 1, uint32(block.timestamp));

        opScribe.setBar(1);
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setUpFeedsAndOpPokeOnce(uint128 val, uint32 age) private {
        // Create and whitelist bar many feeds.
        LibHelpers.Feed[] memory feeds_ =
            LibHelpers.makeFeeds(1, opScribe.bar());
        for (uint i; i < feeds_.length; i++) {
            // @todo Fix IScribeOptimistic tests lift/drop issue.
            //opScribe.lift(feeds_[i].pubKey);
        }

        IScribe.PokeData memory pokeData = IScribe.PokeData(val, age);

        IScribe.SchnorrSignatureData memory schnorrSignatureData =
            LibHelpers.makeSchnorrSignature(feeds_, pokeData, WAT);

        // forgefmt: disable-next-item
        IScribeOptimistic.ECDSASignatureData memory ecdsaSignatureData =
            LibHelpers.makeECDSASignature(
                feeds_[0],
                pokeData,
                schnorrSignatureData,
                WAT
            );

        IScribeOptimistic(address(opScribe)).opPoke(
            pokeData, schnorrSignatureData, ecdsaSignatureData
        );
    }

    function _warpToEndOfOpChallengePeriod() private {
        uint opChallengePeriod = opScribe.opChallengePeriod();

        vm.warp(block.timestamp + opChallengePeriod);
    }
}
