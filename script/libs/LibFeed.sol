// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSchnorrExtended} from "./LibSchnorrExtended.sol";
import {LibSecp256k1Extended} from "./LibSecp256k1Extended.sol";

/**
 * @title LibFeed
 *
 * @notice Solidity library for feeds
 */
library LibFeed {
    using LibSchnorrExtended for LibSecp256k1.Point;
    using LibSchnorrExtended for uint;
    using LibSchnorrExtended for uint[];
    using LibSecp256k1Extended for uint;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for Feed;
    using LibFeed for Feed[];

    Vm internal constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    /// @dev Feed encapsulates a private key, derived public key, and the
    ///      corresponding feed id.
    struct Feed {
        uint privKey;
        LibSecp256k1.Point pubKey;
        uint8 id;
    }

    /// @dev Returns a new feed instance with private key `privKey`.
    function newFeed(uint privKey) internal returns (Feed memory) {
        LibSecp256k1.Point memory pubKey = privKey.derivePublicKey();

        return Feed({
            privKey: privKey,
            pubKey: pubKey,
            id: uint8(uint(uint160(pubKey.toAddress())) >> 152)
        });
    }

    /// @dev Returns a ECDSA signature of type IScribe.ECDSAData
    ///      signing `message` via `self`'s private key.
    function signECDSA(Feed memory self, bytes32 message)
        internal
        pure
        returns (IScribe.ECDSAData memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(self.privKey, message);

        return IScribe.ECDSAData(v, r, s);
    }

    /// @dev Returns a Schnorr signature of type IScribe.SchnorrData
    ///      signing `message` via `self`'s private key.
    function signSchnorr(Feed memory self, bytes32 message)
        internal
        returns (IScribe.SchnorrData memory)
    {
        (uint signature, address commitment) = self.privKey.signMessage(message);

        return IScribe.SchnorrData({
            signature: bytes32(signature),
            commitment: commitment,
            feedIds: abi.encodePacked(self.id)
        });
    }

    /// @dev Returns a Schnorr multi-signature (aggregated signature) of type
    ///      IScribe.SchnorrData signing `message` via `selfs`' private keys.
    function signSchnorr(Feed[] memory selfs, bytes32 message)
        internal
        returns (IScribe.SchnorrData memory)
    {
        // Create multi-signature.
        uint[] memory privKeys = new uint[](selfs.length);
        for (uint i; i < selfs.length; i++) {
            privKeys[i] = selfs[i].privKey;
        }
        (uint signature, address commitment) = privKeys.signMessage(message);

        // Create blob of feedIds.
        bytes memory feedIds;
        for (uint i; i < selfs.length; i++) {
            feedIds = abi.encodePacked(feedIds, selfs[i].id);
        }

        return IScribe.SchnorrData({
            signature: bytes32(signature),
            commitment: commitment,
            feedIds: feedIds
        });
    }
}
