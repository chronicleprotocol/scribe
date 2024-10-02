// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

/**
 * @title Rescuer
 *
 * @notice Contract to recover ETH from offboarded ScribeOptimistic instances
 *
 * @dev Deployment:
 *      ```bash
 *      $ forge create script/rescue/Rescuer.sol:Rescuer \
 *          --constructor-args $INITIAL_AUTHED \
 *          --keystore $KEYSTORE \
 *          --password $KEYSTORE_PASSWORD \
 *          --rpc-url $RPC_URL \
 *          --verifier-url $ETHERSCAN_API_URL \
 *          --etherscan-api-key $ETHERSCAN_API_KEY
 *      ```
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract Rescuer is Auth {
    using LibSecp256k1 for LibSecp256k1.Point;

    /// @notice Emitted when successfully recovered ETH funds.
    /// @param caller The caller's address.
    /// @param opScribe The ScribeOptimistic instance the ETH got recovered
    ///                 from.
    /// @param amount The amount of ETH recovered.
    event Recovered(
        address indexed caller, address indexed opScribe, uint amount
    );

    /// @notice Emitted when successfully withdrawed ETH from this contract.
    /// @param caller The caller's address.
    /// @param receiver The receiver
    ///                 from.
    /// @param amount The amount of ETH recovered.
    event Withdrawed(
        address indexed caller, address indexed receiver, uint amount
    );

    constructor(address initialAuthed) Auth(initialAuthed) {}

    receive() external payable {}

    /// @notice Withdraws `amount` ETH held in contract to `receiver`.
    ///
    /// @dev Only callable by auth'ed address.
    function withdraw(address payable receiver, uint amount) external auth {
        (bool ok,) = receiver.call{value: amount}("");
        require(ok);

        emit Withdrawed(msg.sender, receiver, amount);
    }

    /// @notice Rescues ETH from ScribeOptimistic instance `opScribe`.
    ///
    /// @dev Note that `opScribe` MUST be deactivated.
    /// @dev Note that validator key pair SHALL be only used once and generated
    ///      via a CSPRNG.
    ///
    /// @dev Only callable by auth'ed address.
    function suck(
        address opScribe,
        LibSecp256k1.Point memory pubKey,
        IScribe.ECDSAData memory registrationSig,
        uint32 pokeDataAge,
        IScribe.ECDSAData memory opPokeSig
    ) external auth {
        require(IAuth(opScribe).authed(address(this)));

        address validator = pubKey.toAddress();
        uint8 validatorId = uint8(uint(uint160(validator)) >> 152);

        uint balanceBefore = address(this).balance;

        // Fail if instance has feeds lifted, ie is not deactivated.
        require(IScribe(opScribe).feeds().length == 0);

        // Construct pokeData.
        IScribe.PokeData memory pokeData =
            IScribe.PokeData({val: uint128(0), age: pokeDataAge});

        // Construct invalid Schnorr signature.
        IScribe.SchnorrData memory schnorrSig = IScribe.SchnorrData({
            signature: bytes32(0),
            commitment: address(0),
            feedIds: hex""
        });

        // Lift validator.
        IScribe(opScribe).lift(pubKey, registrationSig);

        // Perform opPoke.
        IScribeOptimistic(opScribe).opPoke(pokeData, schnorrSig, opPokeSig);

        // Perform opChallenge.
        bool ok = IScribeOptimistic(opScribe).opChallenge(schnorrSig);
        require(ok);

        // Drop validator again.
        IScribe(opScribe).drop(validatorId);

        // Compute amount of ETH received as challenge reward.
        uint amount = address(this).balance - balanceBefore;

        // Emit event.
        emit Recovered(msg.sender, opScribe, amount);
    }
}
