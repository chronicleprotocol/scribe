pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSchnorrExtended} from "./LibSchnorrExtended.sol";
import {LibSecp256k1Extended} from "./LibSecp256k1Extended.sol";

/**
 * @title LibPublicKeyVerifier
 *
 * @dev Solidity library to verify a set of public key does not break
 *      assumptions in Scribe's Schnorr signature scheme.
 *
 * @dev Note that the `verifyPublicKeys` function has a runtime of
 *      ω(2^#pubKeys). Consider running it with a high memory limit to not run
 *      into out-of-gas errors.
 */
library LibPublicKeyVerifier {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1Extended for uint;
    using LibSchnorrExtended for LibSecp256k1.Point[];
    using LibSignerSet for LibSignerSet.SignerSetConstructor;

    struct PublicKeyVerifier {
        LibSignerSet.SignerSetConstructor signerSetConstructor;
        mapping(address => LibSignerSet.SignerSet) lookupTable;
    }

    /// @dev Verifies that no subset of a given set of public keys compute to
    ///      the same aggregated public key. If two distinct sets of public keys
    ///      with same aggregated public key is found, the two sets are returned.
    ///
    /// @return True if public keys have no linear relationship, false
    ///         otherwise.
    /// @return Set of public keys
    /// @return Set of public keys
    function verifyPublicKeys(
        PublicKeyVerifier storage self,
        LibSecp256k1.Point[] memory pubKeys
    )
        internal
        returns (bool, LibSecp256k1.Point[] memory, LibSecp256k1.Point[] memory)
    {
        // Generate all possible signer sets (subsets) from set of public keys.
        LibSignerSet.SignerSet[] memory signerSets;
        signerSets = _generateSignerSets(self.signerSetConstructor, pubKeys);

        for (uint i; i < signerSets.length; i++) {
            // Continue if empty set.
            if (signerSets[i].pubKeys.length == 0) {
                continue;
            }

            // Compute aggregated pubKey and derive address.
            LibSecp256k1.Point memory aggPubKey;
            aggPubKey = signerSets[i].pubKeys.aggregatePublicKeys();
            address addr = aggPubKey.toAddress();

            // Fail if address (i.e. aggPubKey) already known.
            if (self.lookupTable[addr].pubKeys.length != 0) {
                LibSecp256k1.Point[] memory set1;
                set1 = self.lookupTable[addr].pubKeys;

                LibSecp256k1.Point[] memory set2;
                set2 = signerSets[i].pubKeys;

                // Set 1 and set 2 compute to same aggregated public key.
                // Their public keys therefore have a linear relationship.
                return (false, set1, set2);
            }

            // Otherwise add address (i.e. aggPubKey) to lookupTable.
            self.lookupTable[addr] = signerSets[i];
        }

        return (true, new LibSecp256k1.Point[](0), new LibSecp256k1.Point[](0));
    }

    function _generateSignerSets(
        LibSignerSet.SignerSetConstructor storage signerSetConstructor,
        LibSecp256k1.Point[] memory pubKeys
    ) private returns (LibSignerSet.SignerSet[] memory) {
        // The total number of subsets of pubKeys is 2^pubKeys.length.
        uint totalSignerSets = 1 << pubKeys.length;

        LibSignerSet.SignerSet[] memory signerSets;
        signerSets = new LibSignerSet.SignerSet[](totalSignerSets);

        for (uint i; i < totalSignerSets; i++) {
            for (uint j; j < pubKeys.length; j++) {
                if (i & (1 << j) != 0) {
                    signerSetConstructor.add(pubKeys[j]);
                }
            }

            // Add signerSet to signersSets.
            signerSets[i] = signerSetConstructor.finalize();

            // Reset signerSetConstructor.
            signerSetConstructor.reset();
        }

        return signerSets;
    }
}

library LibSignerSet {
    using LibSecp256k1 for LibSecp256k1.Point;

    struct SignerSet {
        LibSecp256k1.Point[] pubKeys;
    }

    // Note that constructor type is needed because types containing mappings cannot
    // be loaded into memory.
    struct SignerSetConstructor {
        SignerSet signerSet;
        mapping(address => bool) saved;
    }

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
