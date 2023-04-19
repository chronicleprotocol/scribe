pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSecp256k1Extended} from "script/libs/LibSecp256k1Extended.sol";
import {LibDissig} from "script/libs/LibDissig.sol";

abstract contract LibSecp256k1ExtendedTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    function testDifferentialFuzz_derivePublicKey(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory got;
        LibSecp256k1.Point memory want;

        got = LibSecp256k1Extended.derivePublicKey(privKey);
        want = LibDissig.toPoint(privKey);

        assertEq(got.x, want.x);
        assertEq(got.y, want.y);
    }

    function testDifferentialFuzz_mul(uint privKey, uint scalar) public {
        // Bound privKey to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory got;
        LibSecp256k1.Point memory want;

        got = LibSecp256k1Extended.mul(
            LibSecp256k1Extended.derivePublicKey(privKey).toJacobian(), scalar
        ).toAffine();

        // Note that [privKey]G * scalar = [privKey * scalar]G.
        want =
            LibDissig.toPoint(mulmod(privKey, scalar, LibSecp256k1Extended.P));

        assertEq(got.x, want.x);
        assertEq(got.y, want.y);
    }

    function testDifferentialFuzz_add(uint privKey1, uint privKey2) public {
        // Bound privKeys to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKey1 = bound(privKey1, 1, LibSecp256k1.Q() - 1);
        privKey2 = bound(privKey2, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory p1;
        LibSecp256k1.Point memory p2;
        LibSecp256k1.Point memory got;
        LibSecp256k1.Point memory want;

        p1 = LibSecp256k1Extended.derivePublicKey(privKey1);
        p2 = LibSecp256k1Extended.derivePublicKey(privKey2);

        // forgefmt: disable-next-item
        got = LibSecp256k1Extended.add(
            p1.toJacobian(),
            p2.toJacobian()
        ).toAffine();
        want = LibDissig.aggregateToPoint(privKey1, privKey2);

        assertEq(got.x, want.x);
        assertEq(got.y, want.y);
    }

    function testDifferentialFuzz_double(uint privKey) public {
        // Bound privKey to secp256k1's order, i.e. privKeys ∊ [1, Q).
        privKey = bound(privKey, 1, LibSecp256k1.Q() - 1);

        LibSecp256k1.Point memory p;
        LibSecp256k1.Point memory got;
        LibSecp256k1.Point memory want;

        p = LibSecp256k1Extended.derivePublicKey(privKey);

        got = LibSecp256k1Extended.double(p.toJacobian()).toAffine();
        want = LibDissig.aggregateToPoint(privKey, privKey);

        assertEq(got.x, want.x);
        assertEq(got.y, want.y);
    }
}
