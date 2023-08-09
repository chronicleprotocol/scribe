// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {StdStyle} from "forge-std/StdStyle.sol";
import {console2} from "forge-std/console2.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSecp256k1Extended} from "./libs/LibSecp256k1Extended.sol";
import {
    LibPublicKeyVerifier, LibSignerSet
} from "./libs/LibPublicKeyVerifier.sol";

/**
 * @title PublicKeyVerifier
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
 *         $ forge script script/PublicKeyVerifier.s.sol:PublicKeyVerifierScript \
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
contract PublicKeyVerifier is Script {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1Extended for uint;
    using LibPublicKeyVerifier for LibPublicKeyVerifier.PublicKeyVerifier;

    LibSecp256k1.Point[] pubKeys;

    LibPublicKeyVerifier.PublicKeyVerifier verifier;

    function _pubKeys() internal returns (LibSecp256k1.Point[] memory) {
        // Use private keys during testing to see linear relationships easier.
        //pubKeys.push(uint(2).derivePublicKey());
        //pubKeys.push(uint(3).derivePublicKey());
        //pubKeys.push(uint(4).derivePublicKey());
        //pubKeys.push(uint(5).derivePublicKey());
        // -> Fails because 2 + 3 = 5

        // @todo Add pubKey to be lifted.
        /*
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
        */

        return pubKeys;
    }

    function run() public {
        bool ok;
        LibSecp256k1.Point[] memory set1;
        LibSecp256k1.Point[] memory set2;
        (ok, set1, set2) = verifier.verifyPublicKeys(_pubKeys());

        if (!ok) {
            console2.log(
                StdStyle.red(
                    "[FAIL] Different sets of public keys compute to same aggregated public key"
                )
            );
            console2.log("Set1 = {");
            for (uint j; j < set1.length; j++) {
                console2.log(string.concat("    "), _pubKeyToString(set1[j]));
            }
            console2.log("}");
            console2.log("Set2 = {");
            for (uint j; j < set2.length; j++) {
                console2.log(string.concat("    "), _pubKeyToString(set2[j]));
            }
            console2.log("}");

            revert(); // Fail to have non-zero exit code
        } else {
            console2.log(
                StdStyle.green(
                    "[PASS] No sets of public keys with same aggregated public key found"
                )
            );
        }
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
