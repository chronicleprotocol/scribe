pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibScribeECCRef} from "../utils/LibScribeECCRef.sol";

contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    Handler handler;

    function setUp() public {
        // setUp for invariant tests.
        handler = new Handler();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.aggregate.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
        targetContract(address(handler));
    }

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

    /*//////////////////////////////////////////////////////////////
                            INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function invariant_aggregate_neverReverts() public {
        assertFalse(handler.ghost_reverted());
    }

    /*//////////////////////////////////////////////////////////////
                               BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    // @todo Refactor to use solidity-generators lib.

    // Cost: ~21,000 gas
    function testGas_aggregate_2Points() public pure {
        LibSecp256k1.Point memory p1;
        LibSecp256k1.Point memory p2;

        // forgefmt: disable-start
        p1.x = 59295962801117472859457908919941473389380284132224861839820747729565200149877;
        p1.y = 24099691209996290925259367678540227198235484593389470330605641003500238088869;
        p2.x = 64851089525758040367579466304167382929103413010644732883909758786071989980222;
        p2.y = 32130083105762379295362112976003784487250141102104285101756103858151914741514;
        // forgefmt: disable-end

        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](2);
        points[0] = p1;
        points[1] = p2;

        points.aggregate();
    }

    // Cost: ~33,000 gas
    function testGas_aggregate_13Points() public pure {
        LibSecp256k1.Point memory p1;
        LibSecp256k1.Point memory p2;

        // forgefmt: disable-start
        p1.x = 59295962801117472859457908919941473389380284132224861839820747729565200149877;
        p1.y = 24099691209996290925259367678540227198235484593389470330605641003500238088869;
        p2.x = 64851089525758040367579466304167382929103413010644732883909758786071989980222;
        p2.y = 32130083105762379295362112976003784487250141102104285101756103858151914741514;
        // forgefmt: disable-end

        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](13);
        points[0] = p1;
        points[1] = p2;
        points[2] = p2;
        points[3] = p2;
        points[4] = p2;
        points[5] = p2;
        points[6] = p2;
        points[7] = p2;
        points[8] = p2;
        points[9] = p2;
        points[10] = p2;
        points[11] = p2;
        points[12] = p2;

        points.aggregate();
    }
}

/*//////////////////////////////////////////////////////////////
                     INVARIANT TEST HELPERS
//////////////////////////////////////////////////////////////*/

contract Handler {
    Executor public immutable executor;

    bool public ghost_reverted;

    constructor() {
        executor = new Executor();
    }

    function aggregate(LibSecp256k1.Point[] memory points) external {
        // Note that the executor is needed because try-catch is only utilizable
        // for contract creations and external calls.
        try executor.aggregate(points) {}
        catch {
            ghost_reverted = true;
        }
    }
}

contract Executor {
    using LibSecp256k1 for LibSecp256k1.Point[];

    function aggregate(LibSecp256k1.Point[] memory points) external pure {
        points.aggregate();
    }
}
