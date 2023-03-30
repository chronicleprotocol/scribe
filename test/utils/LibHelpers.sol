pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibScribeECCRef} from "./LibScribeECCRef.sol";

library LibHelpers {
    using LibSecp256k1 for LibSecp256k1.Point;

    Vm private constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    /*//////////////////////////////////////////////////////////////
                                 FEEDS
    //////////////////////////////////////////////////////////////*/

    struct Feed {
        uint privKey;
        LibSecp256k1.Point pubKey;
    }

    function makeFeed(uint privKey) internal returns (Feed memory) {
        return Feed(privKey, LibScribeECCRef.scalarMultiplication(privKey));
    }

    function makeFeeds(uint startPrivKey, uint stopPrivKey)
        internal
        returns (Feed[] memory)
    {
        require(
            startPrivKey <= stopPrivKey,
            "LibHelpers::makeFeeds: start privKey > stop privKey"
        );

        // Note that stopPrivKey is included.
        Feed[] memory feeds = new Feed[](1 + stopPrivKey - startPrivKey);

        for (uint i = startPrivKey; i < stopPrivKey + 1; i++) {
            feeds[i - startPrivKey] =
                Feed(i, LibScribeECCRef.scalarMultiplication(i));
        }

        return feeds;
    }

    /*//////////////////////////////////////////////////////////////
                               SIGNATURES
    //////////////////////////////////////////////////////////////*/

    function makeSchnorrSignature(
        Feed[] memory signers,
        IScribe.PokeData memory pokeData,
        bytes32 wat
    ) internal pure returns (IScribe.SchnorrSignatureData memory) {
        bytes32 message = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                wat
            )
        );

        address[] memory signerAddrs = new address[](signers.length);
        for (uint i; i < signers.length; i++) {
            signerAddrs[i] = signers[i].pubKey.toAddress();
        }
        signerAddrs = sortAddresses(signerAddrs);

        // @todo Implement once Schnorr signature verification is enabled.
        bytes32 signature = bytes32("chronicle");
        address commitment = address(0xdead);

        return IScribe.SchnorrSignatureData(signerAddrs, signature, commitment);
    }

    function makeECDSASignature(
        Feed memory signer,
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrSignatureData memory schnorrSignatureData,
        bytes32 wat
    ) internal pure returns (IScribe.ECDSASignatureData memory) {
        bytes32 message = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                abi.encodePacked(schnorrSignatureData.signers),
                schnorrSignatureData.signature,
                schnorrSignatureData.commitment,
                wat
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privKey, message);

        return IScribe.ECDSASignatureData(v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                                 OTHERS
    //////////////////////////////////////////////////////////////*/

    function constructOpCommitment(
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrSignatureData memory schnorrSignatureData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                pokeData.val,
                pokeData.age,
                abi.encodePacked(schnorrSignatureData.signers),
                schnorrSignatureData.signature,
                schnorrSignatureData.commitment
            )
        );
    }

    function sortAddresses(address[] memory addrs)
        internal
        pure
        returns (address[] memory)
    {
        for (uint i = 1; i < addrs.length; i++) {
            for (
                uint j = i;
                j > 0 && uint160(addrs[j - 1]) > uint160(addrs[j]);
                j--
            ) {
                address tmp = addrs[j];
                addrs[j] = addrs[j - 1];
                addrs[j - 1] = tmp;
            }
        }

        return addrs;
    }
}
