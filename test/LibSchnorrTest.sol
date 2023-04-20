pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {LibSchnorr} from "src/libs/LibSchnorr.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSchnorrExtended} from "script/libs/LibSchnorrExtended.sol";
import {LibSecp256k1Extended} from "script/libs/LibSecp256k1Extended.sol";

abstract contract LibSchnorrTest is Test {
    using LibSchnorrExtended for uint;
    using LibSchnorrExtended for uint[];
    using LibSchnorrExtended for LibSecp256k1.Point[];
    using LibSecp256k1Extended for uint;

    // @todo Implement Differential Testing with Dissig

    function testFuzz_verifySignature_SingleSigner(
        uint privKeySeed,
        bytes32 message
    ) public {
        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Compute pubKey.
        LibSecp256k1.Point memory pubKey = privKey.derivePublicKey();

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Signature is _not_ verifiable if one of the following cases hold:
        // - commitment == address(0)
        // - pubKey.x == 0
        // - signature == 0
        // - signature >= Q
        bool shouldBeOk = true;
        if (commitment == address(0)) shouldBeOk = false;
        if (pubKey.x == 0) shouldBeOk = false;
        if (signature == 0) shouldBeOk = false;
        if (signature >= LibSecp256k1.Q()) shouldBeOk = false;

        // Signature verification should equal expected value.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertEq(ok, shouldBeOk);
    }

    function testFuzz_verifySignature_MultipleSigners(
        uint[] memory privKeySeeds,
        bytes32 message
    ) public {
        vm.assume(privKeySeeds.length > 1);
        // Keep low to not run out-of-gas.
        vm.assume(privKeySeeds.length < 50);

        uint[] memory privKeys = new uint[](privKeySeeds.length);
        for (uint i; i < privKeySeeds.length; i++) {
            // Let each privKey ∊ [2, Q).
            // Note that we allow double signing.
            privKeys[i] = bound(privKeySeeds[i], 2, LibSecp256k1.Q() - 1);
        }

        // Make list of public key.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](privKeySeeds.length);
        for (uint i; i < privKeySeeds.length; i++) {
            pubKeys[i] = privKeys[i].derivePublicKey();
        }

        // Compute aggregated public key.
        LibSecp256k1.Point memory aggPubKey = pubKeys.aggregatePublicKeys();

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKeys.signMessage(message);

        // Signature is _not_ verifiable if one of the following cases hold:
        // - commitment == address(0)
        // - pubKey.x == 0
        // - signature == 0
        // - signature >= Q
        bool shouldBeOk = true;
        if (commitment == address(0)) shouldBeOk = false;
        if (aggPubKey.x == 0) shouldBeOk = false;
        if (signature == 0) shouldBeOk = false;
        if (signature >= LibSecp256k1.Q()) shouldBeOk = false;

        // Signature verification should equal expected value.
        bool ok = LibSchnorr.verifySignature(
            pubKeys.aggregatePublicKeys(),
            message,
            bytes32(signature),
            commitment
        );
        assertEq(ok, shouldBeOk);
    }

    function testFuzz_verifySignature_FailsIf_SignatureMutated(
        uint privKeySeed,
        bytes32 message,
        uint signatureMask
    ) public {
        vm.assume(signatureMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Mutate signature.
        signature ^= signatureMask;

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }

    function testFuzz_verifySignature_FailsIf_CommitmentMutated(
        uint privKeySeed,
        bytes32 message,
        uint160 commitmentMask
    ) public {
        vm.assume(commitmentMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Mutate commitment.
        commitment = address(uint160(commitment) ^ commitmentMask);

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }

    function testFuzz_verifySignature_FailsIf_MessageMutated(
        uint privKeySeed,
        bytes32 message,
        uint messageMask
    ) public {
        vm.assume(messageMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Mutate message.
        message = bytes32(uint(message) ^ messageMask);

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }

    function testFuzz_verifySignature_FailsIf_PubKeyMutated(
        uint privKeySeed,
        bytes32 message,
        uint pubKeyXMask,
        uint pubKeyYMask
    ) public {
        vm.assume(pubKeyXMask != 0 || pubKeyYMask != 0);

        // Let privKey ∊ [1, Q).
        uint privKey = bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Compute and mutate pubKey.
        LibSecp256k1.Point memory pubKey = privKey.derivePublicKey();
        pubKey.x = pubKey.x ^ pubKeyXMask;
        pubKey.y = pubKey.y ^ pubKeyYMask;

        // Signature verification should not succeed.
        bool ok = LibSchnorr.verifySignature(
            pubKey, message, bytes32(signature), commitment
        );
        assertFalse(ok);
    }
}
