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
 * @notice Provides IScribeAuth Unit Tests
 */
abstract contract IScribeAuthTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    IScribeAuth scribe;

    mapping(address => bool) addressFilter;

    event FeedLifted(address indexed caller, address indexed feed);
    event FeedDropped(address indexed caller, address indexed feed);
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    function setUp(address scribe_) internal virtual {
        scribe = IScribeAuth(scribe_);
    }

    /*//////////////////////////////////////////////////////////////
                            TEST: DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public virtual {
        // Bar set to 2.
        assertEq(scribe.bar(), 2);

        // Set of feeds empty.
        assertEq(scribe.feeds().length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                     TEST: AUTH PROTECTED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_lift_Single(LibSecp256k1.Point memory pubKey) public {
        vm.assume(!pubKey.isZeroPoint());

        vm.expectEmit(true, true, true, true);
        emit FeedLifted(address(this), pubKey.toAddress());

        scribe.lift(pubKey);

        // Check via feeds(address)(bool).
        assertTrue(scribe.feeds(pubKey.toAddress()));

        // Check via feeds()(address[]).
        address[] memory feeds = scribe.feeds();
        assertEq(feeds.length, 1);
        assertEq(feeds[0], pubKey.toAddress());

        // Lifting the same feed again should not emit an event.
        // However, @todo not sure how to test that.
        scribe.lift(pubKey);
    }

    function test_lift_Single_FailsIf_PubKeyIsZero() public {
        LibSecp256k1.Point memory zeroPoint = LibSecp256k1.Point(0, 0);

        vm.expectRevert();
        scribe.lift(zeroPoint);
    }

    function testFuzz_lift_Multiple(LibSecp256k1.Point[] memory pubKeys)
        public
    {
        for (uint i; i < pubKeys.length; i++) {
            vm.assume(!pubKeys[i].isZeroPoint());
        }

        for (uint i; i < pubKeys.length; i++) {
            // Don't expect event for duplicates.
            if (!addressFilter[pubKeys[i].toAddress()]) {
                vm.expectEmit(true, true, true, true);
                emit FeedLifted(address(this), pubKeys[i].toAddress());
            }
            addressFilter[pubKeys[i].toAddress()] = true;
        }

        scribe.lift(pubKeys);

        // Check via feeds(address)(bool).
        for (uint i; i < pubKeys.length; i++) {
            assertTrue(scribe.feeds(pubKeys[i].toAddress()));
        }

        // Check via feeds()(address[]).
        address[] memory feeds = scribe.feeds();
        for (uint i; i < pubKeys.length; i++) {
            for (uint j; j < feeds.length; j++) {
                // Break inner loop if pubKey found in list of feeds.
                if (pubKeys[i].toAddress() == feeds[j]) {
                    break;
                }

                // Fail if pubKey not found in list of feeds.
                if (j == feeds.length - 1) {
                    assertTrue(false);
                }
            }
        }
    }

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
        address[] memory feeds = scribe.feeds();
        assertEq(feeds.length, 3);
        assertEq(feeds[0], LibSecp256k1.Point(1, 1).toAddress());
        assertEq(feeds[1], pubKey.toAddress());
        assertEq(feeds[2], pubKey.toAddress());
    }

    function testFuzz_setBar(uint8 bar) public {
        vm.assume(bar != 0);

        vm.expectEmit(true, true, true, true);
        emit BarUpdated(address(this), scribe.bar(), bar);

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
        scribe.lift(LibSecp256k1.Point(0, 0));
    }

    function test_lift_Multiple_IsAuthProtected() public {
        LibSecp256k1.Point[] memory pubKeys;

        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        scribe.lift(pubKeys);
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
}
