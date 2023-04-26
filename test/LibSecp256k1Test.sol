pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSecp256k1Extended} from "script/libs/LibSecp256k1Extended.sol";
import {LibDissig} from "script/libs/LibDissig.sol";

abstract contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSecp256k1Extended for uint;

    // -- addAffinePoint --

    function test_addAffinePoint_UsesConstantAmountOfGas(
        LibSecp256k1.JacobianPoint memory jacPoint,
        LibSecp256k1.Point memory p
    ) public {
        // Note that the exact gas usage is not that important.
        uint gasUsageWant = 890;

        uint gasBefore = gasleft();
        jacPoint.addAffinePoint(p);
        uint gasAfter = gasleft();

        uint gasUsageGot = gasBefore - gasAfter;
        assertEq(gasUsageGot, gasUsageWant);
    }

    function test_addAffinePoint_DoesNotRevert(
        LibSecp256k1.JacobianPoint memory jacPoint,
        LibSecp256k1.Point memory p
    ) public {
        jacPoint.addAffinePoint(p);
    }

    /*
    // @todo addAffinePoint differential fuzz test broken...
    function testDifferentialFuzz_addAffinePoint(uint privKeyA, uint privKeyB)
        public
    {
        // Bound privKeys to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKeyA = bound(privKeyA, 1, LibSecp256k1.Q() - 1);
        privKeyB = bound(privKeyB, 1, LibSecp256k1.Q() - 1);

        vm.assume(privKeyA != privKeyB);

        LibSecp256k1.Point memory pointA = privKeyA.derivePublicKey();
        LibSecp256k1.Point memory pointB = privKeyB.derivePublicKey();

        // LibSecp256k1Extended
        LibSecp256k1.Point memory want = LibSecp256k1Extended.add(
            pointA.toJacobian(), pointB.toJacobian()
        ).toAffine();

        // LibSecp256k1
        LibSecp256k1.JacobianPoint memory jacPointA = pointA.toJacobian();
        // Note that addAffinePoint writes directly into jacPointA's memory.
        jacPointA.addAffinePoint(pointB);

        LibSecp256k1.Point memory got = jacPointA.toAffine();

        // LibDissig
        LibSecp256k1.Point memory pointC = LibDissig.toPoint(privKeyA);
        LibSecp256k1.Point memory pointD = LibDissig.toPoint(privKeyB);
        LibSecp256k1.Point memory pointE = LibDissig.aggregateToPoint(privKeyA, privKeyB);

        if (pointE.x == want.x) {
            console2.log("pointE == want");
            return;
        }
        if (pointE.x == got.x) {
            console2.log("pointE == got");
            return;
        }
        console2.log("NOPE");

        //assertEq(want.x, got.x);
        //assertEq(want.y, got.y);
    }
    */

    // -- toAddress --

    function testDifferentialFuzz_toAddress(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        address want = vm.addr(privKey);
        address got = LibDissig.toPoint(privKey).toAddress();

        assertEq(want, got);
    }

    // -- toAffine --

    function test_toAffine_DoesNotRevert(
        LibSecp256k1.JacobianPoint memory jacPoint
    ) public {
        jacPoint.toAffine();
    }

    function testDifferentialFuzz_toAffine(uint x, uint y, uint z) public {
        console2.log("NOT IMPLEMENTED");
        return;

        LibSecp256k1.JacobianPoint memory jac;
        jac = LibSecp256k1.JacobianPoint(x, y, z);

        //LibSecp256k1.Point memory got jac.toAffine();
    }

    function test_toJacobian_toAffine(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory want = privKey.derivePublicKey();
        LibSecp256k1.Point memory got = want.toJacobian().toAffine();

        assertEq(want.x, got.x);
        assertEq(want.y, got.y);
    }
}
