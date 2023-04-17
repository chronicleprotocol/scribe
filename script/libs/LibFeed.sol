pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {IScribe_Optimized as IScribe} from "src/IScribe_Optimized.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibSchnorrExtended} from "./LibSchnorrExtended.sol";
import {LibSecp256k1Extended} from "./LibSecp256k1Extended.sol";

library LibFeed {
    using LibSchnorrExtended for LibSecp256k1.Point;
    using LibSchnorrExtended for uint;
    using LibSchnorrExtended for uint[];
    using LibSecp256k1Extended for uint;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for Feed;
    using LibFeed for Feed[];

    Vm private constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    struct Feed {
        uint privKey;
        LibSecp256k1.Point pubKey;
        uint8 index;
    }

    function newFeed(uint privKey, uint8 index)
        internal
        returns (Feed memory)
    {
        return Feed({
            privKey: privKey,
            pubKey: privKey.derivePublicKey(),
            index: index
        });
    }

    function signECDSA(Feed memory self, bytes32 message)
        internal
        pure
        returns (IScribe.ECDSASignatureData memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(self.privKey, message);

        return IScribe.ECDSASignatureData(v, r, s);
    }

    function signSchnorr(Feed memory self, bytes32 message)
        internal
        returns (IScribe.SchnorrSignatureData memory)
    {
        (uint signature, address commitment) = self.privKey.signMessage(message);

        return IScribe.SchnorrSignatureData({
            signature: bytes32(signature),
            commitment: commitment,
            signersBlob: abi.encodePacked(self.index)
        });
    }

    function signSchnorr(Feed[] memory selfs, bytes32 message)
        internal
        returns (IScribe.SchnorrSignatureData memory)
    {
        // Create multi-signature.
        uint[] memory privKeys = new uint[](selfs.length);
        for (uint i; i < selfs.length; i++) {
            privKeys[i] = selfs[i].privKey;
        }
        (uint signature, address commitment) = privKeys.signMessage(message);

        // Create signersBlob with sorted indexes.
        bytes memory signersBlob;
        uint8[] memory sortedIndexes = selfs.getIndexesSortedByAddress();
        for (uint i; i < sortedIndexes.length; i++) {
            signersBlob = abi.encodePacked(signersBlob, sortedIndexes[i]);
        }

        return IScribe.SchnorrSignatureData({
            signature: bytes32(signature),
            commitment: commitment,
            signersBlob: signersBlob
        });
    }

    /// @dev Returns the list of `selfs` indexes sorted by `selfs`' addresses.
    function getIndexesSortedByAddress(Feed[] memory selfs)
        internal
        pure
        returns (uint8[] memory)
    {
        // Create array of feeds' indexes.
        uint8[] memory indexes = new uint8[](selfs.length);
        for (uint i; i < selfs.length; i++) {
            indexes[i] = selfs[i].index;
        }

        // Create array of feeds' addresses.
        address[] memory addrs = new address[](selfs.length);
        for (uint i; i < selfs.length; i++) {
            addrs[i] = selfs[i].pubKey.toAddress();
        }

        // Sort indexes array based on addresses array.
        for (uint i = 1; i < selfs.length; i++) {
            for (
                uint j = i;
                j > 0 && uint160(addrs[j - 1]) > uint160(addrs[j]);
                j--
            ) {
                // Swap in indexes array.
                {
                    uint8 tmp = indexes[j];
                    indexes[j] = indexes[j - 1];
                    indexes[j - 1] = tmp;
                }

                // Swap in addresses array.
                {
                    address tmp = addrs[j];
                    addrs[j] = addrs[j - 1];
                    addrs[j - 1] = tmp;
                }
            }
        }

        // Return sorted list of indexes.
        return indexes;
    }
}
