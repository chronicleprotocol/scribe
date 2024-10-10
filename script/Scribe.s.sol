// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {Chronicle_BASE_QUOTE_COUNTER as Scribe} from "src/Scribe.sol";
// @todo          ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibRandom} from "./libs/LibRandom.sol";
import {LibFeed} from "./libs/LibFeed.sol";

/**
 * @notice Scribe Management Script
 */
contract ScribeScript is Script {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;

    /// @dev Deploys a new Scribe instance with `initialAuthed` being the address
    ///      initially auth'ed. Note that zero address is kissed directly after
    ///      deployment.
    function deploy(address initialAuthed, bytes32 wat) public virtual {
        vm.startBroadcast();
        require(msg.sender == initialAuthed, "Deployer must be initial auth'ed");
        address deployed = address(new Scribe(initialAuthed, wat));
        IToll(deployed).kiss(address(0));
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
    }

    // -- IScribe Functions --

    // -- Mutating Functions

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
        bool isFeed = IScribe(self).feeds(pubKey.toAddress());
        require(!isFeed, "Public key already lifted");

        address recovered =
            ecrecover(IScribe(self).feedRegistrationMessage(), v, r, s);
        require(
            recovered != address(0),
            "Invalid ECDSA signature: recovered address is zero"
        );
        require(
            pubKey.toAddress() == recovered,
            "Invalid ECDSA signature: does not recover to feed's address"
        );

        vm.startBroadcast();
        IScribe(self).lift(pubKey, ecdsaData);
        vm.stopBroadcast();

        console2.log("Lifted", pubKey.toAddress());
    }

    /// @dev Lifts feeds with public keys `pubKeyXCoordinates` `pubKeyYCoordinates`.
    ///      Note that the ECDSA signatures signing
    ///      IScribe::feedRegistrationMessage() must be valid.
    function lift(
        address self,
        uint[] memory pubKeyXCoordinates,
        uint[] memory pubKeyYCoordinates,
        uint8[] memory vs,
        bytes32[] memory rs,
        bytes32[] memory ss
    ) public {
        uint len = pubKeyXCoordinates.length;
        require(
            len == pubKeyYCoordinates.length,
            "pubKeyYCoordinates length mismatch"
        );
        require(len == vs.length, "vs length mismatch");
        require(len == rs.length, "rs length mismatch");
        require(len == ss.length, "ss length mismatch");

        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](len);
        for (uint i; i < len; i++) {
            pubKeys[i].x = pubKeyXCoordinates[i];
            pubKeys[i].y = pubKeyYCoordinates[i];

            require(
                !pubKeys[i].isZeroPoint(), "Public key cannot be zero point"
            );
            require(
                pubKeys[i].isOnCurve(),
                "Public key must be valid secp256k1 point"
            );
            bool isFeed = IScribe(self).feeds(pubKeys[i].toAddress());
            require(!isFeed, "Public key already lifted");
        }

        IScribe.ECDSAData[] memory ecdsaDatas = new IScribe.ECDSAData[](len);
        for (uint i; i < len; i++) {
            ecdsaDatas[i].v = vs[i];
            ecdsaDatas[i].r = rs[i];
            ecdsaDatas[i].s = ss[i];

            address recovered = ecrecover(
                IScribe(self).feedRegistrationMessage(),
                ecdsaDatas[i].v,
                ecdsaDatas[i].r,
                ecdsaDatas[i].s
            );
            require(
                recovered != address(0),
                "Invalid ECDSA signature: recovered address is zero"
            );
            require(
                pubKeys[i].toAddress() == recovered,
                "Invalid ECDSA signature: does not recover to feed's address"
            );
        }

        vm.startBroadcast();
        IScribe(self).lift(pubKeys, ecdsaDatas);
        vm.stopBroadcast();

        console2.log("Lifted:");
        for (uint i; i < len; i++) {
            console2.log("  ", pubKeys[i].toAddress());
        }
    }

    /// @dev Drops feed with id `feedId`.
    function drop(address self, uint8 feedId) public {
        vm.startBroadcast();
        IScribe(self).drop(feedId);
        vm.stopBroadcast();

        console2.log("Dropped", feedId);
    }

    /// @dev Drops feeds with ids `feedIds`.
    function drop(address self, uint8[] memory feedIds) public {
        vm.startBroadcast();
        IScribe(self).drop(feedIds);
        vm.stopBroadcast();

        for (uint i; i < feedIds.length; i++) {
            console2.log("Dropped", feedIds[i]);
        }
    }

    /// @dev Pokes `self` with arguments given via calldata payload `payload`.
    ///
    /// @dev Note that this function can be used to simulate - or execute -
    ///      pokes with an already fully constructed payload.
    ///
    /// @dev Call via:
    ///      ```bash
    ///      $ forge script \
    ///           --keystore $KEYSTORE \
    ///           --password $KEYSTORE_PASSWORD \
    ///           --broadcast \
    ///           --rpc-url $RPC_URL \
    ///           --sig $(cast calldata "pokeRaw(address,bytes)" $SCRIBE $PAYLOAD) \
    ///           -vvvvv \
    ///           script/dev/Scribe.s.sol:ScribeScript
    ///      ```
    ///
    ///      Note to remove `--broadcast` to just simulate the poke.
    function pokeRaw(address self, bytes calldata payload) public {
        // Note to remove first 4 bytes, ie the function selector, from the
        // payload to receive the arguments.
        bytes calldata args = payload[4:];

        // Decode arguments into opPoke argument types.
        IScribe.PokeData memory pokeData;
        IScribe.SchnorrData memory schnorrData;
        (pokeData, schnorrData) =
            abi.decode(args, (IScribe.PokeData, IScribe.SchnorrData));

        // Print arguments.
        console2.log("PokeData");
        console2.log("- val :", pokeData.val);
        console2.log("- age :", pokeData.age);
        console2.log("SchnorrData");
        console2.log("- signature  :", uint(schnorrData.signature));
        console2.log("- commitment :", schnorrData.commitment);
        console2.log("- feedIds    :", vm.toString(schnorrData.feedIds));

        // Execute poke..
        vm.startBroadcast();
        IScribe(self).poke(pokeData, schnorrData);
        vm.stopBroadcast();
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

    // -- Offboarding Functions --

    /// @dev Step 1 of deactivating instance `self`.
    ///
    /// @dev Deactivating an instance means:
    ///      - Its value is zero
    ///      - There are no lifted feeds
    ///      - Bar is set to type(uint8).max
    ///
    /// @dev Note that deactivation MUST be executed via two distinct
    ///      `forge script` due to forge script's hard requirement to perform
    ///      a simulation. However, simulating deactivation fails because
    ///      the `poke(0)` MUST happen after (in terms of timestamp) the
    ///      `setBar(1)` call. Note that `forge script` simulations run as a
    ///      single tx and therefore at the same timestamp.
    ///
    ///      For more info, see https://github.com/foundry-rs/foundry/issues/6825.
    function deactivate_Step1(address self) public {
        // Get lifted feeds and compute their feed ids.
        address[] memory feeds = IScribe(self).feeds();
        uint8[] memory feedIds = new uint8[](feeds.length);
        for (uint i; i < feeds.length; i++) {
            feedIds[i] = uint8(uint(uint160(feeds[i])) >> 152);
        }

        // Drop all feeds.
        vm.startBroadcast();
        IScribe(self).drop(feedIds);
        vm.stopBroadcast();

        // Set bar to 1.
        vm.startBroadcast();
        IScribe(self).setBar(uint8(1));
        vm.stopBroadcast();
    }

    /// @dev Step 2 of deactivating instance `self`.
    function deactivate_Step2(address self) public {
        // Create new random private key.
        uint privKeySeed = LibRandom.readUint();
        uint privKey = _bound(privKeySeed, 1, LibSecp256k1.Q() - 1);

        // Create feed instance from private key.
        LibFeed.Feed memory feed = LibFeed.newFeed(privKey);

        // Let feed sign feed registration message.
        IScribe.ECDSAData memory ecdsaData;
        ecdsaData = feed.signECDSA(IScribe(self).feedRegistrationMessage());

        // Lift feed.
        vm.startBroadcast();
        IScribe(self).lift(feed.pubKey, ecdsaData);
        vm.stopBroadcast();

        // Create and sign pokeData with value of zero.
        //
        // Note that this disables Scribe's read functions.
        IScribe.PokeData memory pokeData;
        pokeData.val = uint128(0);
        pokeData.age = uint32(block.timestamp);

        IScribe.SchnorrData memory schnorrData;
        schnorrData =
            feed.signSchnorr(IScribe(self).constructPokeMessage(pokeData));

        // Execute poke.
        vm.startBroadcast();
        IScribe(self).poke(pokeData, schnorrData);
        vm.stopBroadcast();

        // Drop feed again.
        vm.startBroadcast();
        IScribe(self).drop(feed.id);
        vm.stopBroadcast();

        // Set bar to type(uint8).max.
        vm.startBroadcast();
        IScribe(self).setBar(type(uint8).max);
        vm.stopBroadcast();
    }

    /// @dev Kills instance `self`.
    ///
    /// @dev Expects instance `self` to be deactivated.
    ///
    /// @dev Note to only call using the `--sender` flag!
    function kill(address self) public {
        // Require self to be deactivated.
        {
            vm.prank(address(0));
            (bool ok, /*val*/ ) = IScribe(self).tryRead();
            require(!ok, "Instance not deactivated: read() does not fail");

            require(
                IScribe(self).feeds().length == 0,
                "Instance not deactivated: Feeds still lifted"
            );
            require(
                IScribe(self).bar() == 255,
                "Instance not deactivated: Bar not type(uint8).max"
            );
        }

        // Get list of auth'ed addresses.
        address[] memory authed = IAuth(self).authed();

        // Renounce auth for each address except msg.sender.
        //
        // Note that msg.sender refers to the current script's caller, i.e. the
        // address signing the actual txs, iff the `--sender` flag was used.
        for (uint i; i < authed.length; i++) {
            if (authed[i] == msg.sender) {
                continue;
            }

            vm.startBroadcast();
            IAuth(self).deny(authed[i]);
            vm.stopBroadcast();
        }

        // Finally renounce auth for msg.sender.
        vm.startBroadcast();
        IAuth(self).deny(msg.sender);
        vm.stopBroadcast();
    }
}
