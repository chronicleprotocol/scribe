// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// forgefmt: disable-start

import {Script, console2 as console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @notice One-shot helper: derives the offboarder feed's deterministic
 *         private key from a string seed, prints the public key coordinates
 *         and the ECDSA signature over Scribe's `feedRegistrationMessage`.
 *
 *         The output is what gets hardcoded into ScribeOffboarder.sol as
 *         constants. Re-run any time to verify the values.
 *
 *         Usage:
 *             forge script script/offboarder/PrintFeedConstants.s.sol -vvv
 */
contract PrintFeedConstantsScript is Script {
    // Derivation: privKey = uint(keccak256(SEED)) mod Q.
    string constant SEED = "Chronicle.ScribeOffboarder.v1";

    // Order of secp256k1.
    uint constant Q =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // Scribe's feed-registration message (constant across all scribes):
    //     keccak256("\x19Ethereum Signed Message:\n32" ‖
    //               keccak256("Chronicle Feed Registration"))
    bytes32 constant FEED_REGISTRATION_MESSAGE = keccak256(
        abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256("Chronicle Feed Registration")
        )
    );

    function run() public {
        uint privKey = uint(keccak256(bytes(SEED))) % Q;
        require(privKey != 0, "zero privKey");

        Vm.Wallet memory w = vm.createWallet(privKey);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(privKey, FEED_REGISTRATION_MESSAGE);

        uint8 feedId = uint8(uint(uint160(w.addr)) >> 152);

        console.log("------ Offboarder Feed Constants ------");
        console.log("seed:                   ", SEED);
        console.log("feedRegistrationMessage:");
        console.logBytes32(FEED_REGISTRATION_MESSAGE);
        console.log("FEED_PRIV_KEY:");
        console.logBytes32(bytes32(privKey));
        console.log("FEED_PUBKEY_X:");
        console.logBytes32(bytes32(w.publicKeyX));
        console.log("FEED_PUBKEY_Y:");
        console.logBytes32(bytes32(w.publicKeyY));
        console.log("LIFT_ECDSA_V:           ", v);
        console.log("LIFT_ECDSA_R:");
        console.logBytes32(r);
        console.log("LIFT_ECDSA_S:");
        console.logBytes32(s);
        console.log("derived feed address:   ", w.addr);
        console.log("derived feedId:         ", feedId);
    }
}
// forgefmt: disable-end
