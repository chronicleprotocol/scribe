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

        // Sign message.
        uint signature;
        address commitment;
        (signature, commitment) = privKey.signMessage(message);

        // Signature verification should succeed.
        bool ok = LibSchnorr.verifySignature(
            privKey.derivePublicKey(), message, bytes32(signature), commitment
        );
        assertTrue(ok);
    }

    // Fails if:
    // privKey[0] = 3
    // privKey[1] = 115792089237316195423570985008687907852837564279074904382605163141518161494334
    // => sum(privKeys) >= Q
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
        if (commitment == address(0)) return;
        if (aggPubKey.x == 0) return;
        if (signature == 0) return;
        if (signature >= LibSecp256k1.Q()) return;

        // Signature verification should succeed.
        bool ok = LibSchnorr.verifySignature(
            pubKeys.aggregatePublicKeys(),
            message,
            bytes32(signature),
            commitment
        );
        assertTrue(ok);
    }
}
