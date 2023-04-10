pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

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

    function signSchnorrMessage(
        Feed[] memory signers,
        IScribe scribeInstance,
        IScribe.PokeData memory pokeData
    ) internal view returns (IScribe.SchnorrSignatureData memory) {
        // Get message to sign from scribe instance.
        bytes32 message = scribeInstance.constructPokeMessage(pokeData);

        // Create sorted list of signers' addresses.
        address[] memory signerAddrs = new address[](signers.length);
        for (uint i; i < signers.length; i++) {
            signerAddrs[i] = signers[i].pubKey.toAddress();
        }
        signerAddrs = sortAddresses(signerAddrs);

        // @todo Sign message via Schnorr.
        bytes32 signature = bytes32("chronicle");
        address commitment = address(0xdead);

        return IScribe.SchnorrSignatureData(signerAddrs, signature, commitment);
    }

    function signSchnorrMessage(Feed memory signer, bytes32 message)
        //IScribe.scribeInstance,
        //IScribe.PokeData memory pokeData
        internal
        returns (IScribe.SchnorrSignatureData memory)
    {
        // Get message to sign from scribe instance.
        //bytes32 message = scribeInstance.constructSchnorrMessage(pokeData);

        // Select k.
        //
        // Let k = H(privKey ‖ m)
        uint k = uint(keccak256(abi.encodePacked(signer.privKey, message)));

        // Compute R = [k]G.
        LibSecp256k1.Point memory R = LibScribeECCRef.scalarMultiplication(k);

        // Let commitment be the Ethereum address of R.
        address commitment = R.toAddress();

        // Construct e = H(Pₓ ‖ Pₚ ‖ Rₑ ‖ m)
        uint e = uint(
            keccak256(
                abi.encodePacked(
                    signer.pubKey.x,
                    uint8(signer.pubKey.yParity()),
                    message,
                    commitment
                )
            )
        );

        // Compute s = k - (e * x)       (mod Q)
        //           = k + (Q - (e * x)) (mod Q)
        bytes32 s = bytes32(
            addmod(
                k,
                LibSecp256k1.Q() - mulmod(e, signer.privKey, LibSecp256k1.Q()),
                LibSecp256k1.Q()
            )
        );

        address[] memory signers = new address[](1);
        signers[0] = signer.pubKey.toAddress();

        IScribe.SchnorrSignatureData memory schnorrData;
        schnorrData.signers = signers;
        schnorrData.signature = s;
        schnorrData.commitment = commitment;

        return schnorrData;
    }

    function makeECDSASignature(
        Feed memory signer,
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrSignatureData memory schnorrData,
        bytes32 wat
    ) internal pure returns (IScribe.ECDSASignatureData memory) {
        bytes32 message = keccak256(
            abi.encode(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                abi.encodePacked(schnorrData.signers),
                schnorrData.signature,
                schnorrData.commitment,
                wat
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privKey, message);

        return IScribe.ECDSASignatureData(v, r, s);
    }

    function makeECDSASignature(Feed memory signer, bytes32 message)
        internal
        pure
        returns (IScribe.ECDSASignatureData memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privKey, message);

        return IScribe.ECDSASignatureData(v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                                 OTHERS
    //////////////////////////////////////////////////////////////*/

    // @todo Same as makeECDSASignature?
    function constructOpCommitment(
        IScribe.PokeData memory pokeData,
        IScribe.SchnorrSignatureData memory schnorrData,
        bytes32 wat
    ) internal pure returns (bytes32) {
        // Note that opCommitment is constructed the same way as an ECDSA
        // message.
        return keccak256(
            abi.encode(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                abi.encodePacked(schnorrData.signers),
                schnorrData.signature,
                schnorrData.commitment,
                wat
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
