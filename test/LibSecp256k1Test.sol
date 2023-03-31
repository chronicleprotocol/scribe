pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibScribeECCRef} from "./utils/LibScribeECCRef.sol";

abstract contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    /*//////////////////////////////////////////////////////////////
                               UNIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_aggregate_ReturnsZeroPointIf_PointsIsEmpty() public {
        LibSecp256k1.Point[] memory points;

        LibSecp256k1.Point memory got = points.aggregate();
        assertTrue(got.isZeroPoint());
    }

    function test_aggregate_ReturnsZeroPointIf_AdditionWithSameXCoordinates()
        public
    {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](2);
        points[0] = LibSecp256k1.Point(1, 1);
        points[1] = LibSecp256k1.Point(1, 2);

        LibSecp256k1.Point memory got = points.aggregate();
        assertTrue(got.isZeroPoint());
    }

    function testFuzz_aggregate_NeverReverts(LibSecp256k1.Point[] memory points)
        public
    {
        points.aggregate();
    }

    /*//////////////////////////////////////////////////////////////
                        DIFFERENTIAL FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testDifferentialFuzz_aggregate(uint[] memory scalars) public {
        vm.assume(scalars.length > 1);
        vm.assume(scalars.length < 50);

        // Bound scalars to secp256k1's order, i.e. scalar ∊ [1, Q).
        for (uint i; i < scalars.length; i++) {
            scalars[i] = bound(scalars[i], 1, LibSecp256k1.Q() - 1);
        }

        // Compute points from scalars.
        LibSecp256k1.Point[] memory points =
            new LibSecp256k1.Point[](scalars.length);
        for (uint i; i < scalars.length; i++) {
            points[i] = LibScribeECCRef.scalarMultiplication(scalars[i]);
        }

        // Compute sum of points.
        LibSecp256k1.Point memory want = LibScribeECCRef.pointAddition(points);
        LibSecp256k1.Point memory got = points.aggregate();

        assertEq(want.x, got.x);
        assertEq(want.y, got.y);
    }

    function testDifferentialFuzz_toAddress(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        address want = vm.addr(privKey);
        address got = LibScribeECCRef.scalarMultiplication(privKey).toAddress();

        assertEq(want, got);
    }
}
