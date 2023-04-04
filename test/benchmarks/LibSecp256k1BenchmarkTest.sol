pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {arange} from "solidity-generators/Generators.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibScribeECCRef} from "../utils/LibScribeECCRef.sol";

abstract contract LibSecp256k1BenchmarkTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    function testBenchmark_aggregate() public {
        uint[] memory list = arange(uint(0), 100, 5);

        console2.log("# LibSecp256k1::aggregate Benchmark:");
        console2.log("");

        for (uint i; i < list.length; i++) {
            if (list[i] == 0) {
                continue;
            }

            LibSecp256k1.Point[] memory points =
                new LibSecp256k1.Point[](list[i]);

            // Fill list of points to compute with the generator.
            for (uint j; j < points.length; j++) {
                points[j] = LibSecp256k1.G();
            }

            // Second point should have different x coordinate than first, so
            // just change the first points x coordinate.
            points[0].x++;

            uint gasBefore = gasleft();
            LibSecp256k1.Point memory result; // = points.aggregate();
            uint gasAfter = gasleft();
            uint gasUsed = gasBefore - gasAfter;

            assertFalse(result.isZeroPoint());

            console2.log("  Number of Points :", points.length);
            console2.log("  Gas Usage        :", gasUsed);
            console2.log("  -----");
        }
    }

    function testBenchmark_toAffine() public {
        console2.log("# LibSecp256k1::toAffine Benchmark:");
        console2.log("");

        LibSecp256k1.Point memory p1;
        LibSecp256k1.Point memory p2;

        // forgefmt: disable-start
        p1.x = 59295962801117472859457908919941473389380284132224861839820747729565200149877;
        p1.y = 24099691209996290925259367678540227198235484593389470330605641003500238088869;
        p2.x = 64851089525758040367579466304167382929103413010644732883909758786071989980222;
        p2.y = 32130083105762379295362112976003784487250141102104285101756103858151914741514;
        // forgefmt: disable-end

        LibSecp256k1.JacobianPoint memory jacP = p1.toJacobian();
        jacP.addAffinePoint(p2);

        uint gasBefore = gasleft();
        jacP.toAffine();
        uint gasAfter = gasleft();
        uint gasUsed = gasBefore - gasAfter;

        console2.log("  Gas Usage        :", gasUsed);
    }
}
