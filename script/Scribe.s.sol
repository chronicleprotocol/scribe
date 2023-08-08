pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";

import {IScribe} from "src/IScribe.sol";
import {Scribe} from "src/Scribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

contract Chronicle_BASE_QUOTE_COUNTER is Scribe {
    // @todo Adjust name's BASE, QUOTE and COUNTER.
    constructor(address initialAuthed, bytes32 wat_)
        Scribe(initialAuthed, wat_)
    {}
}

/**
 * @notice Scribe Management Script
 */
contract ScribeScript is Script {
    using LibSecp256k1 for LibSecp256k1.Point;

    /// @dev Deploys a new Scribe instance via Greenhouse instance `greenhouse`
    ///      and salt `salt` with `initialAuthed` being the address initially
    ///      auth'ed.
    function deploy(
        address greenhouse,
        bytes32 salt,
        address initialAuthed,
        bytes32 wat
    ) public virtual {
        // Create creation code with constructor arguments.
        bytes memory creationCode = abi.encodePacked(
            type(Chronicle_BASE_QUOTE_COUNTER).creationCode,
            // @todo Adjust name's BASE, QUOTE and COUNTER.
            abi.encode(initialAuthed, wat)
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        // Plant creation code via greenhouse.
        vm.startBroadcast();
        IGreenhouse(greenhouse).plant(salt, creationCode);
        vm.stopBroadcast();

        console2.log("-- Deployment Info Start --");
        console2.log("name:", "Chronicle_ETH_USD_1");
        console2.log("contract:", "Scribe");
        console2.log("chain:", "");
        console2.log("chainId:", uint(0));
        console2.log("address:", deployed);
        console2.log("salt:", vm.toString(salt));
        console2.log("version:", "");
        console2.log("environment:", "");
        console2.log("deployedAt:", "");
        console2.log("-- Deployment Info End --");
    }

    // -- IScribe Functions --

    /// @dev Sets bar of `self` to `bar`.
    function setBar(address self, uint8 bar) public {
        require(bar != 0, "Bar cannot be zero");

        vm.startBroadcast();
        IScribe(self).setBar(bar);
        vm.stopBroadcast();

        console2.log("Bar set to", bar);
    }

    /// @dev Lifts feed with public key `pubKeyXCoordinate` `pubKeyYCoordinate`.
    ///      Note that the ECDSA signature signing
    ///      IScribe::feedRegistrationMessage() must be valid.
    function lift(
        address self,
        uint pubKeyXCoordinate,
        uint pubKeyYCoordinate,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        LibSecp256k1.Point memory pubKey;
        pubKey.x = pubKeyXCoordinate;
        pubKey.y = pubKeyYCoordinate;

        IScribe.ECDSAData memory ecdsaData;
        ecdsaData.v = v;
        ecdsaData.r = r;
        ecdsaData.s = s;

        require(!pubKey.isZeroPoint(), "Public key cannot be zero point");
        require(pubKey.isOnCurve(), "Public key must be valid secp256k1 point");
        bool isFeed;
        (isFeed, /*feedIndex*/ ) = IScribe(self).feeds(pubKey.toAddress());
        require(!isFeed, "Public key already lifted");

        address recovered =
            ecrecover(IScribe(self).feedRegistrationMessage(), v, r, s);
        require(
            recovered != address(0),
            "Invalid ECDSA signature: recovered address is zero"
        );

        address expected =
            LibSecp256k1.Point(pubKeyXCoordinate, pubKeyYCoordinate).toAddress();
        require(
            expected == recovered,
            "Invalid ECDSA signature: does not recover to feed's address"
        );

        vm.startBroadcast();
        IScribe(self).lift(pubKey, ecdsaData);
        vm.stopBroadcast();

        console2.log("Lifted", pubKey.toAddress());
    }

    /// @dev Drops feed with index `feedIndex`.
    function drop(address self, uint feedIndex) public {
        require(feedIndex != 0, "Feed index cannot be zero");

        vm.startBroadcast();
        IScribe(self).drop(feedIndex);
        vm.stopBroadcast();

        console2.log("Dropped", feedIndex);
    }

    // -- IAuth Functions --

    /// @dev Grants auth to address `who`.
    function rely(address self, address who) public {
        vm.startBroadcast();
        IAuth(self).rely(who);
        vm.stopBroadcast();

        console2.log("Relied", who);
    }

    /// @dev Renounces auth from address `who`.
    function deny(address self, address who) public {
        vm.startBroadcast();
        IAuth(self).deny(who);
        vm.stopBroadcast();

        console2.log("Denied", who);
    }

    // -- IToll Functions --

    /// @dev Grants toll to address `who`.
    function kiss(address self, address who) public {
        vm.startBroadcast();
        IToll(self).kiss(who);
        vm.stopBroadcast();

        console2.log("Kissed", who);
    }

    /// @dev Renounces toll from address `who`.
    function diss(address self, address who) public {
        vm.startBroadcast();
        IToll(self).diss(who);
        vm.stopBroadcast();

        console2.log("Dissed", who);
    }
}
