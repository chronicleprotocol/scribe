pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSchnorr} from "src/libs/LibSchnorr.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibHelpers} from "./utils/LibHelpers.sol";

contract LibSchnorrEMERGENCYTest is Test {
    // forgefmt:disable-start
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    // Original Test from Oorbit.
    function test_James_Call() public {
        LibSecp256k1.Point memory pubKey;
        pubKey.x = 0x4ac136efaf3ad5f0fcc8edea50f4a0d24d4055f419e0971ab86497ed49b4b5e2;
        pubKey.y = 1;

        uint sig = 0x6fbf8e1f139635ef5b3d37fa0a73a0af4dfd3ca223131b325a1e618ac4fb7a5a;

        address commitment = 0x1475D10105c2695D79B8ff21629F9917E43D205e;

        uint price = 0x0000000000000000000000000000000000000000000000001bc16d674ec80000;
        uint age = 0x0000000000000000000000000000000000000000000000000000000000000001;
        uint msghash = uint(keccak256(abi.encodePacked(price, age)));

        bool ok = LibSchnorr.verifySignature(
            pubKey, bytes32(msghash), bytes32(sig), commitment
        );
        assertTrue(ok);
    }

    function test_SchnorrSoliditySpec() public {
        LibHelpers.Feed memory feed = LibHelpers.makeFeed(1);
        bytes32 message = keccak256("message");

        IScribe.SchnorrSignatureData memory schnorrData;
        schnorrData = LibHelpers.signSchnorrMessage(
            feed,
            message
        );

        bool ok = LibSchnorr.verifySignature(
            feed.pubKey, message, schnorrData.signature, schnorrData.commitment
        );
        assertTrue(ok);
    }


    // Test created via musig-wrapper.
    function test_musigWrapper() public {
        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](3);
        pubKeys[0].x = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;
        pubKeys[0].y = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8;
        pubKeys[1].x = 0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5;
        pubKeys[1].y = 0x1ae168fea63dc339a3c58419466ceaeef7f632653266d0e1236431a950cfe52a;
        pubKeys[2].x = 0xf9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9;
        pubKeys[2].y = 0x388f7b0f632de8140fe337e62a37f3566500a99934c2231b6cb9fd7584b8e672;

        // Compute aggregated public key.
        LibSecp256k1.JacobianPoint memory aggPubKeyAsJac = pubKeys[0].toJacobian();
        for (uint i = 1; i < pubKeys.length; i++) {
            console2.log("aggPubKey.x", aggPubKeyAsJac.toAffine().x);
            console2.log("aggPubKey.y", aggPubKeyAsJac.toAffine().y);
            aggPubKeyAsJac.addAffinePoint(pubKeys[i]);
        }
        LibSecp256k1.Point memory aggPubKey = aggPubKeyAsJac.toAffine();

        console2.log("aggPubKey.x", aggPubKey.x);
        console2.log("aggPubKey.y", aggPubKey.y);

        LibSecp256k1.Point memory commitmentPoint;
        commitmentPoint.x = 0xe6c3b22a7a603b81cd2ca17bcaf9c89020127e735fd9e2e9b216f43abe953e60;
        commitmentPoint.y = 0xa9c3a769bbc29afec06bb882478a1f8606909738d5b6c194c052ed00c4caffbc;

        uint sig = 0xc3e1183be6e33109dfc32a253a58e6e43f9e0827dd94551acbd8122ad1841e8a;

        uint msghash = 0x52d35e78fed47971a925cca45a5b29371b0a36c5618c866cabf1fe8e521f41dc;

        bool ok = LibSchnorr.verifySignatureBIP340(
        	aggPubKey, commitmentPoint, bytes32(msghash), bytes32(sig)
        );
        assertTrue(ok);
    }

    // forgefmt: disable-end
}
