pragma solidity ^0.8.16;

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title LibSecp256k1Extended
 *
 * @notice
 *
 * @author Modified from Jordi Baylina's [ecsol](https://github.com/jbaylina/ecsol/blob/c2256afad126b7500e6f879a9369b100e47d435d/ec.sol).
 */
library LibSecp256k1Extended {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSecp256k1Extended for LibSecp256k1.JacobianPoint;

    //--------------------------------------------------------------------------
    // Constants
    //
    // Taken from https://www.secg.org/sec2-v2.pdf.
    // See section 2.4.1 "Recommended Parameters secp256k1".

    uint internal constant A = 0;
    uint internal constant B = 7;
    uint internal constant P =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    //--------------------------------------------------------------------------
    // API Functions

    function derivePublicKey(uint privKey)
        internal
        pure
        returns (LibSecp256k1.Point memory)
    {
        LibSecp256k1.JacobianPoint memory jacResult;
        jacResult = LibSecp256k1.G().toJacobian().mul(privKey);

        uint z = invMod(jacResult.z);

        return LibSecp256k1.Point({
            x: mulmod(jacResult.x, z, P),
            y: mulmod(jacResult.y, z, P)
        });
    }

    function mul(LibSecp256k1.JacobianPoint memory self, uint scalar)
        internal
        pure
        returns (LibSecp256k1.JacobianPoint memory)
    {
        if (scalar == 0) {
            return LibSecp256k1.ZERO_POINT().toJacobian();
        }

        LibSecp256k1.JacobianPoint memory copy;
        copy = self;

        LibSecp256k1.JacobianPoint memory result;
        result = LibSecp256k1.ZERO_POINT().toJacobian();

        while (scalar != 0) {
            if (scalar % 2 == 1) {
                result = result.add(copy);
            }
            scalar /= 2;
            copy = copy.double();
        }

        return result;
    }

    function double(LibSecp256k1.JacobianPoint memory self)
        internal
        pure
        returns (LibSecp256k1.JacobianPoint memory)
    {
        return self.add(self);
    }

    function add(
        LibSecp256k1.JacobianPoint memory self,
        LibSecp256k1.JacobianPoint memory p
    ) internal pure returns (LibSecp256k1.JacobianPoint memory) {
        if (self.x == 0 && self.y == 0) {
            return p;
        }
        if (p.x == 0 && p.y == 0) {
            return self;
        }

        uint l;
        uint lz;
        uint da;
        uint db;
        LibSecp256k1.JacobianPoint memory result;

        if (self.x == p.x && self.y == p.y) {
            (l, lz) = _mul(self.x, self.z, self.x, self.z);
            (l, lz) = _mul(l, lz, 3, 1);
            (l, lz) = _add(l, lz, A, 1);

            (da, db) = _mul(self.y, self.z, 2, 1);
        } else {
            (l, lz) = _sub(p.y, p.z, self.y, self.z);
            (da, db) = _sub(p.x, p.z, self.x, self.z);
        }

        (l, lz) = _div(l, lz, da, db);

        (result.x, da) = _mul(l, lz, l, lz);
        (result.x, da) = _sub(result.x, da, self.x, self.z);
        (result.x, da) = _sub(result.x, da, p.x, p.z);

        (result.y, db) = _sub(self.x, self.z, result.x, da);
        (result.y, db) = _mul(result.y, db, l, lz);
        (result.y, db) = _sub(result.y, db, self.y, self.z);

        if (da != db) {
            result.x = mulmod(result.x, db, P);
            result.y = mulmod(result.y, da, P);
            result.z = mulmod(da, db, P);
        } else {
            result.z = da;
        }

        return result;
    }

    function invMod(uint x) internal pure returns (uint) {
        uint t;
        uint q;
        uint newT = 1;
        uint r = P;

        while (x != 0) {
            q = r / x;
            (t, newT) = (newT, addmod(t, (P - mulmod(q, newT, P)), P));
            (r, x) = (x, r - (q * x));
        }

        return t;
    }

    //--------------------------------------------------------------------------
    // Private Helpers

    function _add(uint x1, uint z1, uint x2, uint z2)
        private
        pure
        returns (uint, uint)
    {
        uint x3 = addmod(mulmod(z2, x1, P), mulmod(x2, z1, P), P);
        uint z3 = mulmod(z1, z2, P);

        return (x3, z3);
    }

    function _sub(uint x1, uint z1, uint x2, uint z2)
        private
        pure
        returns (uint, uint)
    {
        uint x3 = addmod(mulmod(z2, x1, P), mulmod(P - x2, z1, P), P);
        uint z3 = mulmod(z1, z2, P);

        return (x3, z3);
    }

    function _mul(uint x1, uint z1, uint x2, uint z2)
        private
        pure
        returns (uint, uint)
    {
        uint x3 = mulmod(x1, x2, P);
        uint z3 = mulmod(z1, z2, P);

        return (x3, z3);
    }

    function _div(uint x1, uint z1, uint x2, uint z2)
        private
        pure
        returns (uint, uint)
    {
        uint x3 = mulmod(x1, z2, P);
        uint z3 = mulmod(z1, x2, P);

        return (x3, z3);
    }
}
