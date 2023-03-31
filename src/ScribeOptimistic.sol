pragma solidity ^0.8.16;

import {IScribeOptimistic} from "./IScribeOptimistic.sol";
import {IScribeOptimisticAuth} from "./IScribeOptimisticAuth.sol";

import {Scribe} from "./Scribe.sol";
import {IScribe} from "./IScribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

contract ScribeOptimistic is
    IScribeOptimistic,
    IScribeOptimisticAuth,
    Scribe
{
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    uint16 public opChallengePeriod;

    address public opFeed;
    bytes32 public opCommitment;

    PokeData private _opPokeData;

    modifier dropOpPokeData() {
        _;

        emit OpPokeDataDropped(msg.sender, _opPokeData.val, _opPokeData.age);
        delete _opPokeData;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // Note to have a non-zero challenge period.
        opChallengePeriod = 1 hours;
        emit OpChallengePeriodUpdated(msg.sender, 0, 1 hours);
    }

    /*
     * @todo Disable op stuff after gov action for x hours.
     */

    /*//////////////////////////////////////////////////////////////
                     OPTIMISTIC POKE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function opPoke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData,
        ECDSASignatureData calldata ecdsaSignatureData
    ) external {
        // Revert if pokeData's age is not fresher than current finalized
        // pokeData's age.
        if (pokeData.age <= _currentAge()) {
            revert StaleMessage(pokeData.age, _currentAge());
        }

        // Revert if a non-finalized, i.e. still challengeable, opPokeData
        // exists.
        if (_opExistsAndNotFinalized()) {
            revert InChallengePeriod();
        }

        // Construct the message expected to be signed via ECDSA.
        bytes32 ecdsaMessage = _constructECDSAMessage(pokeData, schnorrSignatureData);

        // Recover ECDSA signer.
        address signer = ecrecover(
            ecdsaMessage,
            ecdsaSignatureData.v,
            ecdsaSignatureData.r,
            ecdsaSignatureData.s
        );

        // Revert if signer is not feed.
        if (_feeds[signer].isZeroPoint()) {
            revert SignerNotFeed(signer);
        }

        // Store the signer and bind them to their pokeData and corresponding
        // schnorrSignatureData.
        // Note that the ecdsaMessage is used as commitment. While ecdsaMessage
        // also includes the wat and "Ethereum signed message" prefix, which are
        // not necessary for the commitment, its saves some gas not having to
        // compute another hash.
        opFeed = signer;
        opCommitment = ecdsaMessage;

        // If opPokeData exists, consider moving it to the pokeData storage.
        // This frees the opPokeData storage. Note that opPokeData is already
        // guaranteed to either being non-existing or finalized.
        //
        // Note to only overwrite the pokeData storage if the opPokeData's age
        // is actually fresher.
        if (_opExistsAndFinalized() && _opPokeData.age > _pokeData.age) {
            _pokeData = _opPokeData;
        }

        // Store given pokeData in opPokeData storage. Note to set the
        // opPokeData's age to the current timestamp and NOT the given
        // pokeData's age.
        _opPokeData.val = pokeData.val;
        _opPokeData.age = uint32(block.timestamp);
    }

    // @audit DOS via schnorrSignatureData.signers length?
    //        YES! Should require length == bar!
    //        For consistency, also require in Scribe.
    function opChallenge(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData
    ) external {
        // Revert if there is no opPokeData to challenge, i.e. non exists or
        // its challenge period is already over.
        if (!_opExistsAndNotFinalized()) {
            revert NoOpPokeToChallenge();
        }

        // Revert if given set of pokeData and corresponding
        // schnorrSignatureData does not match the data opFeed committed
        // themselves to.
        // @todo ^^ Rephrase to use "integrity of arguments".
        // @todo Adjust comment to reflect change to ecdsa message as commitment.
        if (
            _constructECDSAMessage(pokeData, schnorrSignatureData) != opCommitment
        ) {
            revert ArgumentsDoNotMatchOpCommitment(
                _constructECDSAMessage(pokeData, schnorrSignatureData),
                opCommitment
            );
            // @todo Check gas changes if ecdsa message/commitment is stored in var.
        }

        // Decide whether schnorrSignatureData, initially provided by opFeed,
        // is valid.
        bool ok = true;

        if (ok) {
            // Declare as invalid if number of signers is less than bar.
            ok = !(schnorrSignatureData.signers.length < bar);
        }

        LibSecp256k1.Point memory aggPubKey;
        if (ok) {
            // Declare array of secp256k1 points (public keys) with enough capacity
            // to hold each signer's public key.
            LibSecp256k1.Point[] memory pubKeys =
                new LibSecp256k1.Point[](schnorrSignatureData.signers.length);

            // Iterate over the set of signers.
            for (uint i; i < schnorrSignatureData.signers.length; i++) {
                address signer = schnorrSignatureData.signers[i];

                // Declare as invalid if signer is not feed.
                if (_feeds[signer].isZeroPoint()) {
                    ok = false;
                    break;
                }

                // Declare as invalid if signers are not in ascending order.
                // Note that this prevents double signing and ensures there
                // exists only one valid sequence of signers for each set of
                // signers.
                if (i != 0) {
                    uint160 pre = uint160(schnorrSignatureData.signers[i - 1]);
                    if (pre >= uint160(signer)) {
                        ok = false;
                        break;
                    }
                }

                // Add signer's public key to array.
                pubKeys[i] = _feeds[signer];
            }

            // Compute the aggregated public key from the set of signers.
            aggPubKey = pubKeys.aggregate();
        }

        if (ok) {
            // Declare as invalid if Schnorr signature verification fails for
            // pokeData initially provided by opFeed.
            ok = aggPubKey.verifySignature(
                _constructSchnorrMessage(pokeData),
                schnorrSignatureData.signature,
                schnorrSignatureData.commitment
            );
        }

        if (ok) {
            // If opPoke was ok, finalize opPokeData by moving it to the
            // _pokeData slot. Note to only finalize opPokeData if its age is
            // actually fresher than _pokeData's age.
            if (_opPokeData.age > _pokeData.age) {
                _pokeData = _opPokeData;
            }
        } else {
            // If opPoke was not ok, kick opFeed.
            delete _feeds[opFeed];
        }

        // Delete _opPokeData. Either it's stored already in the _pokeData slot
        // or it's invalid.
        delete _opPokeData;
    }

    /*//////////////////////////////////////////////////////////////
                         TOLLED VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function read()
        external
        view
        override(IScribe, Scribe)
        toll
        returns (uint)
    {
        uint val = _currentVal();
        require(val != 0);
        return val;
    }

    function peek()
        external
        view
        override(IScribe, Scribe)
        toll
        returns (uint, bool)
    {
        uint val = _currentVal();
        return (val, val != 0);
    }

    /*//////////////////////////////////////////////////////////////
                           AUTH'ED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @todo Rename to something more like "challengePeriodLength" or
    //       "challengeWindowLength".
    function setOpChallengePeriod(uint16 opChallengePeriod_)
        external
        auth
        dropOpPokeData
    {
        require(opChallengePeriod_ != 0);

        if (opChallengePeriod != opChallengePeriod_) {
            emit OpChallengePeriodUpdated(
                msg.sender, opChallengePeriod, opChallengePeriod_
            );
            opChallengePeriod = opChallengePeriod_;
        }
    }

    /*//////////////////////////////////////////////////////////////
                      OVERRIDDEN SCRIBE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _drop(LibSecp256k1.Point memory pubKey)
        internal
        override(Scribe)
        dropOpPokeData
    {
        super._drop(pubKey);
    }

    function _drop(LibSecp256k1.Point[] memory pubKeys)
        internal
        override(Scribe)
        dropOpPokeData
    {
        super._drop(pubKeys);
    }

    function _setBar(uint8 bar_) internal override(Scribe) dropOpPokeData {
        super._setBar(bar_);
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _constructECDSAMessage(
        PokeData memory pokeData,
        SchnorrSignatureData memory schnorrSignatureData
    ) private pure returns (bytes32) {
        return keccak256(
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
    }

    // @todo The functions below (and their usage) can be optimized with
    //       regards to storage reads and memory caching.
    //       E.g. the _opExists... functions read the _opPokeData slot, and
    //       the _current... functions read the same slot again (_opPokeData
    //       only uses one slot).

    function _opExistsAndFinalized() private view returns (bool) {
        uint32 age = _opPokeData.age;

        return age != 0 && age + opChallengePeriod <= uint32(block.timestamp);
    }

    function _opExistsAndNotFinalized() private view returns (bool) {
        uint32 age = _opPokeData.age;

        return age != 0 && age + opChallengePeriod > uint32(block.timestamp);
    }

    function _currentVal() private view returns (uint128) {
        if (_opExistsAndFinalized()) {
            return _opPokeData.val;
        } else {
            return _pokeData.val;
        }
    }

    function _currentAge() private view returns (uint32) {
        if (_opExistsAndFinalized()) {
            return _opPokeData.age;
        } else {
            return _pokeData.age;
        }
    }
}
