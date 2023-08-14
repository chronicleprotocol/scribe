// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";

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
            type(Scribe).creationCode, abi.encode(initialAuthed, wat)
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        // Plant creation code via greenhouse.
        vm.startBroadcast();
        IGreenhouse(greenhouse).plant(salt, creationCode);
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
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

    // -- Offboarding Functions --

    /// @dev !!! DANGER !!!
    ///
    /// @dev Deactivates instance `self`.
    ///
    /// @dev Deactivating an instance means:
    ///      - Its value is zero
    ///      - There are no lifted feeds
    ///      - Bar is set to type(uint8).max
    ///
    /// @dev Note that function _must_ be executed with the `--slow` and
    ///      `--skip-simulation` flags!
    ///
    /// @dev Expected environment variables:
    ///      - PRIVATE_KEY
    ///      - RPC_URL
    ///      - SCRIBE
    ///      - SCRIBE_FLAVOUR
    ///
    /// @dev Run via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///          --private-key $PRIVATE_KEY \
    ///          --broadcast \
    ///          --rpc-url $RPC_URL \
    ///          --sig $(cast calldata "deactivate(address)" "$SCRIBE") \
    ///          --slow \
    ///          --skip-simulation \
    ///          script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
    ///      ```
    function deactivate(address self) public {
        // Get current feeds' indexes.
        uint[] memory feedIndexes;
        ( /*feeds*/ , feedIndexes) = IScribe(self).feeds();

        // Drop all feeds.
        vm.startBroadcast();
        IScribe(self).drop(feedIndexes);
        vm.stopBroadcast();

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
        uint feedIndex = IScribe(self).lift(feed.pubKey, ecdsaData);
        vm.stopBroadcast();

        // Set feed's assigned feedIndex.
        feed.index = uint8(feedIndex);

        // Set bar to 1.
        vm.startBroadcast();
        IScribe(self).setBar(uint8(1));
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
        IScribe(self).drop(feed.index);
        vm.stopBroadcast();

        // Set bar to type(uint8).max.
        vm.startBroadcast();
        IScribe(self).setBar(type(uint8).max);
        vm.stopBroadcast();
    }

    /// @dev !!! DANGER !!!
    ///
    /// @dev Kills instance `self`.
    ///
    /// @dev Killing an instance means:
    ///      - Its deactivated
    ///      - There are no auth'ed addresses
    ///
    ///      Note that this means the ownership of the contract is waived while
    ///      ensuring its value can never be updated again.
    ///
    /// @dev Note that function _must_ be executed with the `--slow` and
    ///      `--skip-simulation` flags!
    ///
    /// @dev Expected environment variables:
    ///      - PRIVATE_KEY
    ///      - RPC_URL
    ///      - SCRIBE
    ///      - SCRIBE_FLAVOUR
    ///
    /// @dev Run via:
    ///
    ///      ```bash
    ///      $ forge script \
    ///          --private-key $PRIVATE_KEY \
    ///          --broadcast \
    ///          --rpc-url $RPC_URL \
    ///          --sig $(cast calldata "kill(address)" "$SCRIBE") \
    ///          --slow \
    ///          --skip-simulation \
    ///          script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
    ///      ```
    function kill(address self) public {
        // Deactivate self.
        deactivate(self);

        // Get list of auth'ed addresses.
        address[] memory authed = IAuth(self).authed();

        // Renounce auth for each address except tx.origin.
        //
        // Note that tx.origin refers to the current script's caller, i.e. the
        // address signing the actual txs.
        for (uint i; i < authed.length; i++) {
            if (authed[i] == tx.origin) {
                continue;
            }

            vm.startBroadcast();
            IAuth(self).deny(authed[i]);
            vm.stopBroadcast();
        }

        // Finally renounce auth for tx.origin.
        vm.startBroadcast();
        IAuth(self).deny(tx.origin);
        vm.stopBroadcast();
    }
}
