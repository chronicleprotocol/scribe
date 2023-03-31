pragma solidity ^0.8.16;

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "src/IScribeOptimisticAuth.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {IScribeAuthTest} from "./IScribeAuthTest.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

/**
 * @notice Provides IScribeOptimisticAuth Unit Tests
 */
abstract contract IScribeOptimisticAuthTest is IScribeAuthTest {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeOptimisticAuth opScribe;

    bytes32 WAT;

    event OpPokeDataDropped(address indexed caller, uint128 val, uint32 age);
    event OpChallengePeriodUpdated(
        address indexed caller,
        uint16 oldOpChallengePeriod,
        uint16 newOpChallengePeriod
    );

    function setUp(address scribe_) internal override(IScribeAuthTest) {
        super.setUp(scribe_);

        opScribe = IScribeOptimisticAuth(scribe_);

        // Cache wat constant.
        WAT = IScribe(address(opScribe)).wat();
    }

    /*//////////////////////////////////////////////////////////////
                            TEST: DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public override(IScribeAuthTest) {
        super.test_deployment();

        // OpChallengePeriod is set to 1 hour.
        assertEq(opScribe.opChallengePeriod(), 1 hours);
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
        LibHelpers.Feed[] memory feeds = LibHelpers.makeFeeds(1, opScribe.bar());
        for (uint i; i < feeds.length; i++) {
            opScribe.lift(feeds[i].pubKey);
        }

        IScribe.PokeData memory pokeData = IScribe.PokeData(val, age);

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

        IScribeOptimistic(address(opScribe)).opPoke(
            pokeData, schnorrSignatureData, ecdsaSignatureData
        );
    }
}
