pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {StdStyle} from "forge-std/StdStyle.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSchnorrExtended} from "./libs/LibSchnorrExtended.sol";
import {LibSecp256k1Extended} from "./libs/LibSecp256k1Extended.sol";

/**
 * @notice Feed Public Key Verifier Script
 *
 * @dev This script verifies that no subset of a given set of public keys
 *      compute to the same aggregated public key.
 *
 *      The script must _never_ fail for a set of lifted feeds!
 *
 * @dev Usage:
 *      1. Add the set of lifted feeds' public keys to `_setUpPubKeys()`
 *      2. Add the new feeds' public key to `_setUpPubKeys()`
 *      3. Run script via:
 *
 *         ```bash
 *         $ forge script script/FeedPublicKeyVerifier.s.sol:FeedPublicKeyVerifierScript \
 *              --memory-limit 10000000000
 *         ```
 *
 *         Note that the script has a runtime and memory consumption of
 *         ω(2^#pubKeys). If the script fails with "EvmError: MemoryLimitOOG",
 *         increase the memory limit.
 *
 * @dev Why?
 *
 *      Scribe uses a simple, but efficient, key aggregation scheme that is
 *      vulnerable to rogue key attacks (see docs/Schnorr.md#key-aggregation-for-multisignatures).
 *      While this attack vector is mitigated via proving a feed has ownership
 *      of their claimed private key, a similar attack is possible if feeds
 *      collude or create their private keys non-cryptographically secure.
 *
 *      Let a set of feeds A have an aggregated public of aggPubKey(A) and leak
 *      the sum of their private keys.
 *
 *      This would allow a distinct set of feeds B to be created with an
 *      aggregated public key of aggPubKey(B) = aggPubKey(A) by choosing private
 *      keys with the same sum as set A's.
 *
 *      Having two distinct sets of feeds' public keys with the same aggregated
 *      public key makes it impossible to determine which set participated in a
 *      Schnorr signature.
 *
 *      Note that this issue only occurs, with non-negligible probability, if
 *      at least one feed does not create their private key cryptographically
 *      sound.
 *
 *      This script verifies that no two distinct subsets of public keys derive
 *      to the same aggregated public key.
 */
contract FeedPublicKeyVerifierScript is Script {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1Extended for uint;
    using LibSchnorrExtended for LibSecp256k1.Point[];
    using LibSignerSet for SignerSetConstructor;

    LibSecp256k1.Point[] pubKeys;

    function _setUpPubKeys() public {
        // Use private keys during testing to see linear relationships easier.
        //pubKeys.push(uint(2).derivePublicKey());
        //pubKeys.push(uint(3).derivePublicKey());
        //pubKeys.push(uint(4).derivePublicKey());
        //pubKeys.push(uint(5).derivePublicKey());
        // -> Fails because 2 + 3 = 5

        // @todo Add pubKey to be lifted.
        pubKeys.push(
            LibSecp256k1.Point({
                x: 0x0000000000000000000000000000000000000000000000000000000000000001,
                y: 0x0000000000000000000000000000000000000000000000000000000000000000
            })
        );

        // @todo Add already lifted pubKeys.
        pubKeys.push(
            LibSecp256k1.Point({
                x: 0x0000000000000000000000000000000000000000000000000000000000000000,
                y: 0x0000000000000000000000000000000000000000000000000000000000000000
            })
        );
        // ...
    }

    mapping(address => SignerSet) results;

    function run() public {
        _setUpPubKeys();

        SignerSet[] memory signerSets = _generateSignerSets();

        for (uint i; i < signerSets.length; i++) {
            // Continue if empty set.
            if (signerSets[i].pubKeys.length == 0) continue;

            // Compute aggregated pubKey and corresponding address.
            LibSecp256k1.Point memory aggPubKey =
                signerSets[i].pubKeys.aggregatePublicKeys();
            address addr = aggPubKey.toAddress();

            // Fail if address was computed already.
            if (results[addr].pubKeys.length != 0) {
                LibSecp256k1.Point[] memory set1 = results[addr].pubKeys;
                LibSecp256k1.Point[] memory set2 = signerSets[i].pubKeys;

                console2.log(
                    StdStyle.red(
                        "[FAIL] Different sets of public keys compute to same aggregated public key"
                    )
                );
                console2.log("Set1 = {");
                for (uint j; j < set1.length; j++) {
                    console2.log(
                        string.concat("    "), _pubKeyToString(set1[j])
                    );
                }
                console2.log("}");
                console2.log("Set2 = {");
                for (uint j; j < set2.length; j++) {
                    console2.log(
                        string.concat("    "), _pubKeyToString(set2[j])
                    );
                }
                console2.log("}");

                revert(); // Fail to have non-zero exit code
            }

            results[addr] = signerSets[i];
        }

        console2.log(
            StdStyle.green(
                "[PASS] No sets of public keys with same aggregated public key found"
            )
        );
    }

    // Needs to be storage variable as type contains mapping.
    SignerSetConstructor signerSet;

    function _generateSignerSets() internal returns (SignerSet[] memory) {
        // The total number of subsets of pubKeys is 2^pubKeys.length.
        uint totalSignerSets = 1 << pubKeys.length;

        SignerSet[] memory signerSets = new SignerSet[](totalSignerSets);

        for (uint i; i < totalSignerSets; i++) {
            for (uint j; j < pubKeys.length; j++) {
                if (i & (1 << j) != 0) {
                    signerSet.add(pubKeys[j]);
                }
            }

            // Add finalized signerSet to signersSets.
            signerSets[i] = signerSet.finalize();

            // Reset signerSet.
            signerSet.reset();
        }

        return signerSets;
    }

    function _pubKeyToString(LibSecp256k1.Point memory pubKey)
        internal
        pure
        returns (string memory)
    {
        string memory result = "pubKey(";
        result = string.concat(
            result, "x: ", vm.toString(pubKey.x), ", y: ", vm.toString(pubKey.y)
        );
        return string.concat(result, ")");
    }
}

struct SignerSet {
    LibSecp256k1.Point[] pubKeys;
}

// Note that constructor type is needed because types containing mappings cannot
// be loaded into memory.
struct SignerSetConstructor {
    SignerSet signerSet;
    mapping(address => bool) saved;
}

library LibSignerSet {
    using LibSecp256k1 for LibSecp256k1.Point;

    function add(
        SignerSetConstructor storage self,
        LibSecp256k1.Point memory pubKey
    ) internal {
        address addr = pubKey.toAddress();
        if (!self.saved[addr]) {
            self.signerSet.pubKeys.push(pubKey);
            self.saved[addr] = true;
        }
    }

    function finalize(SignerSetConstructor storage self)
        internal
        view
        returns (SignerSet memory)
    {
        return self.signerSet;
    }

    function reset(SignerSetConstructor storage self) internal {
        while (self.signerSet.pubKeys.length != 0) {
            LibSecp256k1.Point[] storage pubKeys = self.signerSet.pubKeys;

            address addr = pubKeys[pubKeys.length - 1].toAddress();

            self.saved[addr] = false;
            self.signerSet.pubKeys.pop();
        }
    }
}
