pragma solidity ^0.8.16;

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeAuth} from "src/IScribeAuth.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "src/IScribeOptimisticAuth.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeTest} from "./IScribeTest.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

/**
 * @notice Provides IScribeOptimistic Unit Tests
 */
abstract contract IScribeOptimisticTest is IScribeTest {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeOptimistic opScribe;

    function setUp(address scribe_) internal override(IScribeTest) {
        super.setUp(scribe_);

        opScribe = IScribeOptimistic(scribe_);
    }

    /*//////////////////////////////////////////////////////////////
                            TEST: DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public override(IScribeTest) {
        super.test_deployment();

        assertEq(opScribe.opFeed(), address(0));
        assertEq(opScribe.opCommitment(), bytes32(0));
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
            LibHelpers.constructOpCommitment(pokeData, schnorrSignatureData, WAT)
        );

        // Wait until challenge period over and opPokeData finalizes.
        _warpToEndOfOpChallengePeriod();

        assertEq(scribe.read(), pokeData.val);
        (uint val, bool ok) = scribe.peek();
        assertEq(val, pokeData.val);
        assertTrue(ok);

        // Note that the opFeed & opCommitment is not deleted after finalization.
        assertEq(opScribe.opFeed(), feeds[0].pubKey.toAddress());
        assertEq(
            opScribe.opCommitment(),
            LibHelpers.constructOpCommitment(pokeData, schnorrSignatureData, WAT)
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

            assertEq(scribe.read(), pokeDatas[i].val);
            (uint val, bool ok) = scribe.peek();
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
        scribe.poke(
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

        uint bar = IScribeAuth(address(scribe)).bar();
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

        uint bar = IScribeAuth(address(scribe)).bar();

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
        uint opChallengePeriod =
            IScribeOptimisticAuth(address(opScribe)).opChallengePeriod();
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

    // @todo opChallenge tests.

    /*//////////////////////////////////////////////////////////////
                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _warpToEndOfOpChallengePeriod() private {
        uint opChallengePeriod =
            IScribeOptimisticAuth(address(opScribe)).opChallengePeriod();

        vm.warp(block.timestamp + opChallengePeriod);
    }
}
