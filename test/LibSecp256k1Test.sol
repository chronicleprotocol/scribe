// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSecp256k1Extended} from "script/libs/LibSecp256k1Extended.sol";

abstract contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSecp256k1Extended for uint;

    // -- toAddress --

    function testFuzzDifferential_toAddress(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        address want = vm.addr(privKey);
        address got = privKey.derivePublicKey().toAddress();

        assertEq(want, got);
    }

    // -- toAffine --

    function testFuzz_toAffine_DoesNotRevert(
        LibSecp256k1.JacobianPoint memory jacPoint
    ) public pure {
        jacPoint.toAffine();
    }

    function testFuzz_toJacobian_toAffine(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory want = privKey.derivePublicKey();
        LibSecp256k1.Point memory got = want.toJacobian().toAffine();

        assertEq(want.x, got.x);
        assertEq(want.y, got.y);
    }

    // -- addAffinePoint --

    function testFuzz_addAffinePoint_UsesConstantAmountOfGas(
        LibSecp256k1.JacobianPoint memory jacPoint1,
        LibSecp256k1.Point memory p1,
        LibSecp256k1.JacobianPoint memory jacPoint2,
        LibSecp256k1.Point memory p2
    ) public {
        // Benchmark jacPoint1 + p1.
        uint gasBefore = gasleft();
        jacPoint1.addAffinePoint(p1);
        uint gasAfter = gasleft();
        uint first = gasBefore - gasAfter;

        // Benchmark jacPoint2 + p2.
        gasBefore = gasleft();
        jacPoint2.addAffinePoint(p2);
        gasAfter = gasleft();
        uint second = gasBefore - gasAfter;

        // @todo Not using --via-ir, the second computation uses 3 gas less.
        assertApproxEqAbs(first, second, 3);
    }

    function testFuzz_addAffinePoint_DoesNotRevert(
        LibSecp256k1.JacobianPoint memory jacPoint,
        LibSecp256k1.Point memory p
    ) public pure {
        jacPoint.addAffinePoint(p);
    }

    struct VectorTestCase {
        // Test: p + q = expected
        LibSecp256k1.Point p;
        LibSecp256k1.Point q;
        LibSecp256k1.Point expected;
    }

    function testVectors_addAffinePoint() public {
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "test/vectors/points.js";

        uint[] memory rawCoordinates = abi.decode(vm.ffi(inputs), (uint[]));

        // Parse raw coordinates to VectorTestCases.
        VectorTestCase[] memory testCases =
            new VectorTestCase[](rawCoordinates.length / 2 / 3);
        uint rawCoordinatesCtr;
        for (uint i; i < testCases.length; i++) {
            VectorTestCase memory cur = testCases[i];

            cur.p.x = rawCoordinates[rawCoordinatesCtr++];
            cur.p.y = rawCoordinates[rawCoordinatesCtr++];
            cur.q.x = rawCoordinates[rawCoordinatesCtr++];
            cur.q.y = rawCoordinates[rawCoordinatesCtr++];
            cur.expected.x = rawCoordinates[rawCoordinatesCtr++];
            cur.expected.y = rawCoordinates[rawCoordinatesCtr++];
        }

        // Execute test cases.
        VectorTestCase memory curTestCase;
        LibSecp256k1.JacobianPoint memory jacPoint;
        LibSecp256k1.Point memory result;
        for (uint i; i < testCases.length; i++) {
            curTestCase = testCases[i];

            jacPoint = curTestCase.p.toJacobian();
            jacPoint.addAffinePoint(curTestCase.q);

            result = jacPoint.toAffine();

            if (curTestCase.p.x == curTestCase.q.x) {
                console2.log(
                    string.concat(
                        "Note: Test case #",
                        vm.toString(i),
                        " has same x coordinates:"
                    ),
                    "Expecting zero point as result"
                );

                assertTrue(result.isZeroPoint());
            } else {
                assertEq(result.x, curTestCase.expected.x);
                assertEq(result.y, curTestCase.expected.y);
            }
        }
    }
}
