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

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // Note to have a non-zero challenge period.
        opChallengePeriod = 1 hours;
        emit OpChallengePeriodUpdated(msg.sender, 0, 1 hours);
    }

    receive() external payable {}

    /*
     * @todo Disable op stuff after gov action for x hours.
     */

    /*//////////////////////////////////////////////////////////////
                     OPTIMISTIC POKE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    // @todo Make (and use) documentation:
    // - _pokeData   : PokeData storage slot holding only finalized PokeDatas
    // - _opPokeData : PokeData storage slot. May hold finalized PokeData.
    // - curPokeData : The oracle's current PokeData. One of {_pokeData, _opPOkeData}
    //                 curPokeData = (_opPokeData == Finalized) && _opPokeData.age > _pokeData.age
    //                      ? _opPokeData : _pokeData
    // - usrPokeData : PokeData calldata given by user.
    //
    // - opPokeData  : _opPokeData memory cache.

    function opPoke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData,
        ECDSASignatureData calldata ecdsaData
    ) external payable {
        // Load _opPokeData from storage.
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is finalized.
        bool opPokeDataFinalized =
            opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // Decide current age.
        uint32 age = opPokeDataFinalized && opPokeData.age > _pokeData.age
            ? opPokeData.age
            : _pokeData.age;

        // Revert if pokeData's age is not fresher than current age.
        if (pokeData.age <= age) {
            revert StaleMessage(pokeData.age, age);
        }

        // Revert if _opPokeData is non-finalized, i.e. still challengeable.
        if (!opPokeDataFinalized) {
            revert InChallengePeriod();
        }

        // Construct commitment. The commitment is expected to be signed by a
        // feed via ECDSA.
        bytes32 commitment = _constructCommitment(pokeData, schnorrData);

        // Recover ECDSA signer.
        address signer =
            ecrecover(commitment, ecdsaData.v, ecdsaData.r, ecdsaData.s);

        // Revert if signer is not feed.
        if (_feeds[signer].isZeroPoint()) {
            revert SignerNotFeed(signer);
        }

        // Store the signer and bind them to their commitment.
        opFeed = signer;
        opCommitment = commitment;

        // If _opPokeData provides the current val, move it to the _pokeData
        // storage to free the _opPokeData slot. If the current val is provided
        // by _pokeData, the _opPokeData slot can be overwritten with the new
        // pokeData.
        if (opPokeData.age == age) {
            _pokeData = opPokeData;
        }

        // Store given pokeData in opPokeData storage. Note to set the
        // opPokeData's age to the current timestamp and _not_ the given
        // pokeData's age.
        _opPokeData.val = pokeData.val;
        _opPokeData.age = uint32(block.timestamp);

        // @todo Test for event emission.
        emit OpPoked(
            msg.sender,
            signer,
            pokeData.val,
            uint32(block.timestamp),
            commitment
        );
    }

    // @todo Rename all schnorrSignatureData to schnorrData. Same for ECDSA.

    function opChallenge(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) external payable {
        // Load _opPokeData from storage.
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is challengeable.
        bool opPokeDataChallengeable =
            opPokeData.age + opChallengePeriod > uint32(block.timestamp);

        // Revert if _opPokeData is not challengeable.
        if (!opPokeDataChallengeable) {
            // @todo Rename to "NothingToChallenge"?
            revert NoOpPokeToChallenge();
        }

        // Note that the opCommitment is the ECDSA message signed during
        // opPoke() by the opFeed.
        bytes32 commitment = _constructCommitment(pokeData, schnorrData);

        // Revert if arguments do not match opCommitment.
        if (commitment != opCommitment) {
            revert ArgumentsDoNotMatchOpCommitment(commitment, opCommitment);
        }

        // Verify schnorrSignatureData.
        bool ok;
        bytes memory err;
        (ok, err) = verifySchnorrSignature(pokeData, schnorrData);

        if (ok) {
            // Decide whether _opPokeData stale already.
            bool opPokeDataStale = opPokeData.age < _pokeData.age;

            // If _opPokeData is not stale, finalize it by moving it to the
            // _pokeData slot.
            if (!opPokeDataStale) {
                _pokeData = _opPokeData;
            }

            // @todo Test for event emission.
            emit OpPokeUnsuccessfullyChallenged(msg.sender, commitment);
        } else {
            // Kick opFeed and delete _opPokeData.
            delete _feeds[opFeed];
            delete _opPokeData;

            // Reward challenger the bounty of the contract's current ETH balance.
            uint bounty = address(this).balance;
            payable(msg.sender).call{value: bounty}("");

            // @todo Test for event emission.
            emit OpPokeSuccessfullyChallenged(
                msg.sender, commitment, bounty, err
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                           READ FUNCTIONALITY
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

    function tryRead()
        external
        view
        virtual
        override( /*IScribe,*/ Scribe)
        toll
        returns (bool, uint)
    {
        uint val = _currentVal();
        return (val != 0, val);
    }

    // legacy
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

    function _currentVal() private view returns (uint128) {
        // Load pokeData slots from storage.
        PokeData memory pokeData = _pokeData;
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is finalized.
        bool opPokeDataFinalized =
            opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // Decide current val.
        uint128 val = opPokeDataFinalized && opPokeData.age > pokeData.age
            ? opPokeData.val
            : pokeData.val;

        return val;
    }

    /*//////////////////////////////////////////////////////////////
                         AUTH'ED FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function setOpChallengePeriod(uint16 opChallengePeriod_) external auth {
        require(opChallengePeriod_ != 0);

        if (opChallengePeriod != opChallengePeriod_) {
            emit OpChallengePeriodUpdated(
                msg.sender, opChallengePeriod, opChallengePeriod_
            );
            opChallengePeriod = opChallengePeriod_;
        }

        _dropOpPokeData();
    }

    function _drop(LibSecp256k1.Point memory pubKey)
        internal
        override(Scribe)
    {
        super._drop(pubKey);

        _dropOpPokeData();
    }

    function _drop(LibSecp256k1.Point[] memory pubKeys)
        internal
        override(Scribe)
    {
        super._drop(pubKeys);

        _dropOpPokeData();
    }

    function _setBar(uint8 bar_) internal override(Scribe) {
        super._setBar(bar_);

        _dropOpPokeData();
    }

    function _dropOpPokeData() private {
        // @todo Should include commitment? Events needs refactor anyway.
        emit OpPokeDataDropped(msg.sender, _opPokeData.val, _opPokeData.age);
        delete _opPokeData;
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _constructCommitment(
        PokeData memory pokeData,
        SchnorrSignatureData memory schnorrData
    ) private pure returns (bytes32) {
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
}
