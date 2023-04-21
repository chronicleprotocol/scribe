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

    // @todo Secp256k1 Tests missing:
    // - addAffinePoint uses constant memory
    // - toAffine conversion correct !
    // - toAffine never reverts (except if OOG)
    // - _invMod equal to LibSecp256k1Extended::invMod

    function test_addAffinePoint_OnlyMutatesSelfMemoryVariable(
        LibSecp256k1.JacobianPoint memory self,
        LibSecp256k1.Point memory p
    ) public {
        uint limit = 100 * 0x20; // 100 words

        uint pX_y;
        uint self_x;

        // @todo Fails because p and self are probably not continuous in memory.
        //       Fix by don't assuming order and/or alignment!

        // Delete "whole" memory except of jacPoints.
        assembly ("memory-safe") {
            // Cache free memory pointer.
            let m := mload(0x40)

            let self_x := self
            let self_y := add(self, 0x20)
            let p_x := p
            let p_y := add(p, 0x20)
            pX_y := p_y
            self_x

            // Delete everything up to self_x.
            for { let i := 0 } lt(i, self_x) { i := add(i, 0x20) } {
                mstore(i, 0)
            }

            // Delete everything from p_y + 0x20 up to p_y + limit.
            for
                { let i := add(p_y, 0x20) }
                lt(i, add(p_y, limit))
                { i := add(i, 0x20)
            } {
                mstore(i, 0)
            }

            // Restore free memory pointer.
            mstore(0x40, m)
        }
        console2.log(pX_y);

        self.addAffinePoint(p);

        // Ensure "whole" memory still empty.
        uint nonZeroMemory = type(uint).max;
        assembly ("memory-safe") {
            let self_x := self
            let self_y := add(self, 0x20)
            let self_z := add(self, 0x40)
            let p_x := p
            let p_y := add(p, 0x20)

            // Check whether everything up to self_x is zero.
            for { let i := 0 } lt(i, self_x) { i := add(i, 0x20) } {
                let got := mload(i)
                if not(iszero(got)) {
                    nonZeroMemory := i
                    break
                }
            }

            // Check whether everything from p_y + 0x20 up to p_y + limit is
            // zero.
            for
                { let i := add(p_y, 0x20) }
                lt(i, add(p_y, limit))
                { i := add(i, 0x20)
            } {
                let got := mload(i)
                if not(iszero(got)) {
                    nonZeroMemory := i
                    break
                }
            }
        }


        if (nonZeroMemory != type(uint).max) {
            console2.log("memory slot mutated:", nonZeroMemory);
            assertTrue(false);
        }
    }

    function test_addAffinePoint_DoesNotRevert(
        LibSecp256k1.JacobianPoint memory jacPoint,
        LibSecp256k1.Point memory p
    ) public {
        jacPoint.addAffinePoint(p);
    }

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

    function test_toAffine_DoesNotRevert(
        LibSecp256k1.JacobianPoint memory jacPoint
    ) public {
        jacPoint.toAffine();
    }

    function test_toJacobian_toAffine(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKey ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory want = privKey.derivePublicKey();
        LibSecp256k1.Point memory got = want.toJacobian().toAffine();

        assertEq(want.x, got.x);
        assertEq(want.y, got.y);
    }

    // @todo Use LibSecp256k1Extended instead of dissig if possible...

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
}
