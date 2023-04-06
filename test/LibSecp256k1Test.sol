pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibScribeECCRef} from "./utils/LibScribeECCRef.sol";

abstract contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    // @todo Secp256k1 Tests missing:
    // - addAffinePoint uses constant memory
    // - toAffine conversion correct !
    // - toAffine never reverts (expect if OOG)

    /*//////////////////////////////////////////////////////////////
                        DIFFERENTIAL FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testDifferentialFuzz_addAffinePoint(uint privKeyA, uint privKeyB)
        public
    {
        vm.assume(privKeyA != privKeyB);

        // Bound privKeys to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKeyA = bound(privKeyA, 1, LibSecp256k1.Q() - 1);
        privKeyB = bound(privKeyB, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory pointA =
            LibScribeECCRef.scalarMultiplication(privKeyA);
        LibSecp256k1.Point memory pointB =
            LibScribeECCRef.scalarMultiplication(privKeyB);

        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](2);
        points[0] = pointA;
        points[1] = pointB;

        LibSecp256k1.Point memory want = LibScribeECCRef.pointAddition(points);

        LibSecp256k1.JacobianPoint memory jacPointA = pointA.toJacobian();
        // Note that addAffinePoint directly writes into jacPointA's memory.
        jacPointA.addAffinePoint(pointB);

        LibSecp256k1.Point memory got = jacPointA.toAffine();

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

    /*//////////////////////////////////////////////////////////////
                               BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    // @todo Secp256k1 Benchmarks
}
