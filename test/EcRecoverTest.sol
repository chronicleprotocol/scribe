pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

abstract contract EcRecoverTest is Test {
    // @todo Needs check which tests are necessary. See LibSchnorr todos.

    function testFuzz_RValueOfZero_RecoversAddressZero(
        bytes32 msgHash,
        uint privKeySeed
    ) public {
        // Make privKey. Note to bound it to secp256k1's order,
        // i.e. privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        (uint8 v, /*bytes32 r*/, bytes32 s) = vm.sign(privKey, msgHash);

        bytes32 r = 0;

        assertEq(ecrecover(msgHash, v, r, s), address(0));
    }

    function testFuzz_RValueGreaterThanOrEqualToQ_RecoversAddressZero(
        bytes32 msgHash,
        uint privKeySeed,
        uint rSeed
    ) public {
        // Make privKey. Note to bound it to secp256k1's order,
        // i.e. privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        (uint8 v, /*bytes32 r*/, bytes32 s) = vm.sign(privKey, msgHash);

        bytes32 r = bytes32(bound(rSeed, LibSecp256k1.Q(), type(uint).max));

        assertEq(ecrecover(msgHash, v, r, s), address(0));
    }

    function testFuzz_SValueGreaterThanOrEqualToQ_RecoversAddressZero(
        bytes32 msgHash,
        uint privKeySeed,
        uint sSeed
    ) public {
        // Make privKey. Note to bound it to secp256k1's order,
        // i.e. privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        (uint8 v, bytes32 r, /*bytes32 s*/ ) = vm.sign(privKey, msgHash);

        bytes32 s = bytes32(bound(sSeed, LibSecp256k1.Q(), type(uint).max));

        assertEq(ecrecover(msgHash, v, r, s), address(0));
    }

    function testFuzz_MsgHashOfZero_RecoversSigner(uint privKeySeed) public {
        // Make privKey. Note to bound it to secp256k1's order,
        // i.e. privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        bytes32 msgHash = bytes32(0);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, msgHash);

        assertEq(ecrecover(msgHash, v, r, s), vm.addr(privKey));
    }
}
