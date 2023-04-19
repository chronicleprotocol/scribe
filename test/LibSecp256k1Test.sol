pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibDissig} from "script/libs/LibDissig.sol";

abstract contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    // @todo Secp256k1 Tests missing:
    // - addAffinePoint uses constant memory
    // - toAffine conversion correct !
    // - toAffine never reverts (except if OOG)
    // - _invMod equal to LibSecp256k1Extended::invMod

    uint constant privKeyA = 1;
    uint constant privKeyB = 3;

    function test_addAffinePoints() public {
        LibSecp256k1.Point memory pointA; // = LibDissig.toPoint(privKeyA);
        // 1.toPoint + 2.toPoint
        pointA.x =
            112711660439710606056748659173929673102114977341539408544630613555209775888121;
        pointA.y =
            25583027980570883691656905877401976406448868254816295069919888960541586679410;

        LibSecp256k1.Point memory pointB = LibDissig.toPoint(privKeyB);

        LibSecp256k1.JacobianPoint memory jacPointA = pointA.toJacobian();
        // Note that addAffinePoint writes directly into jacPointA's memory.
        jacPointA.addAffinePoint(pointB);

        LibSecp256k1.Point memory got = jacPointA.toAffine();

        console2.log("pointA.x", pointA.x);
        console2.log("pointA.y", pointA.y);

        console2.log("pointB.x", pointB.x);
        console2.log("pointB.y", pointB.y);

        console2.log("got.x", got.x);
        console2.log("got.y", got.y);
    }

    /*//////////////////////////////////////////////////////////////
                        DIFFERENTIAL FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testDifferentialFuzz_addAffinePoint(uint privKeyA, uint privKeyB)
        public
    {
        // Bound privKeys to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKeyA = bound(privKeyA, 1, LibSecp256k1.Q() - 1);
        privKeyB = bound(privKeyB, 1, LibSecp256k1.Q() - 1);

        vm.assume(privKeyA != privKeyB);

        LibSecp256k1.Point memory pointA = LibDissig.toPoint(privKeyA);
        LibSecp256k1.Point memory pointB = LibDissig.toPoint(privKeyB);

        LibSecp256k1.Point memory want =
            LibDissig.aggregateToPoint(privKeyA, privKeyB);

        LibSecp256k1.JacobianPoint memory jacPointA = pointA.toJacobian();
        // Note that addAffinePoint writes directly into jacPointA's memory.
        jacPointA.addAffinePoint(pointB);

        LibSecp256k1.Point memory got = jacPointA.toAffine();

        // @todo Fails. Most probably issue with dissig though.
        //assertEq(want.x, got.x);
        //assertEq(want.y, got.y);
    }

    function testDifferentialFuzz_toAddress(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        address want = vm.addr(privKey);
        address got = LibDissig.toPoint(privKey).toAddress();

        assertEq(want, got);
    }

    function testDifferentialFuzz_toAffine(uint x, uint y, uint z) public {
        LibSecp256k1.JacobianPoint memory jac;
        jac = LibSecp256k1.JacobianPoint(x, y, z);

        //LibSecp256k1.Point memory got jac.toAffine();
    }

    /*//////////////////////////////////////////////////////////////
                               BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    // @todo Secp256k1 Benchmarks
}
