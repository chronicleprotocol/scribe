pragma solidity ^0.8.16;

import {IScribeOptimistic_Optimized as IScribeOptimistic} from
    "./IScribeOptimistic_Optimized.sol";

import {Scribe_Optimized as Scribe} from "./Scribe_Optimized.sol";
import {IScribe_Optimized as IScribe} from "./IScribe_Optimized.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

/**
 * @title ScribeOptimistic
 *
 * @notice Optimistic!
 *         Thats what the scribe yawps
 *         Can you tame them
 *         By challenging their poke?
 *
 * @dev
 */
contract ScribeOptimistic_Optimized is IScribeOptimistic, Scribe {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    /// @inheritdoc IScribeOptimistic
    uint16 public opChallengePeriod;

    /// @inheritdoc IScribeOptimistic
    uint8 public opFeedIndex;

    // @todo More docs: Is truncated hash.
    //       Why secure? -> 160 bits is enough
    //       Why truncated? -> slot packing
    uint160 private _schnorrDataHash;

    PokeData private _opPokeData;

    /*//////////////////////////////////////////////////////////////
                  CONSTRUCTOR & RECEIVE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    constructor(bytes32 wat_) Scribe(wat_) {
        // Note to have a non-zero challenge period.
        _setOpChallengePeriod(1 hours);
    }

    receive() external payable {}

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

    /// @inheritdoc IScribeOptimistic
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

        // @todo Optimize schnorrData calldata usage. Do not load into memory?
        //       Use assembly, overwrite everything from solc (scratch space, etc)
        //       _after_ everything else is done and no execution given back to solc.
        //       This should lower the memory usage because we overwrite already
        //       allocated memory and don't expand.

        bytes32 ecdsaMessage = _constructOpPokeMessage(pokeData, schnorrData);

        // Recover ECDSA signer.
        address signer =
            ecrecover(ecdsaMessage, ecdsaData.v, ecdsaData.r, ecdsaData.s);

        // Get signer's feedIndex.
        uint feedIndex = _feeds[signer];

        // Revert if signer is not feed.
        if (feedIndex == 0) {
            revert SignerNotFeed(signer);
        }

        // Store the signer and bind them to their commitment.
        opFeedIndex = uint8(feedIndex);
        _schnorrDataHash = uint160(
            uint(
                keccak256(
                    abi.encodePacked(
                        schnorrData.signature,
                        schnorrData.commitment,
                        schnorrData.signersBlob
                    )
                )
            )
        );

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
        // @todo Event emission needs whole schnorrData + pokeMessage
        //       This allows everyone to do:
        //          if (scribe.verifySchnorrSignature(pokeMessage, schnorrData) == false):
        //              opChallenge(schnorrData);
        //emit OpPoked(
        //    msg.sender,
        //    signer,
        //    pokeData.val,
        //    uint32(block.timestamp),
        //    opCommitment
        //);
    }

    /// @inheritdoc IScribeOptimistic
    function opChallenge(SchnorrSignatureData calldata schnorrData)
        external
        payable
        returns (bool)
    {
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

        uint160 schnorrDataHash = uint160(
            uint(
                keccak256(
                    abi.encodePacked(
                        schnorrData.signature,
                        schnorrData.commitment,
                        schnorrData.signersBlob
                    )
                )
            )
        );

        // Revert if arguments do not match opCommitment.
        if (schnorrDataHash != _schnorrDataHash) {
            // @todo Refactor error types.
            //revert ArgumentsDoNotMatchOpCommitment(commitment, opCommitment);
        }

        bytes32 pokeMessage = constructPokeMessage(opPokeData);

        // Verify schnorrSignatureData.
        bool ok;
        bytes memory err;
        (ok, err) = _verifySchnorrSignature(pokeMessage, schnorrData);

        if (ok) {
            // Decide whether _opPokeData stale already.
            bool opPokeDataStale = opPokeData.age < _pokeData.age;

            // If _opPokeData is not stale, finalize it by moving it to the
            // _pokeData slot.
            if (!opPokeDataStale) {
                _pokeData = _opPokeData;
            }
        } else {
            // Drop opFeed and delete invalid _opPokeData.
            // Use address(this) as caller to indicate self-governed drop of
            // feed.
            _drop(address(this), opFeedIndex);

            // Pay challenge bounty to caller.
            _rewardChallenger(payable(msg.sender));

            // @todo Emit event with err.
        }

        return !ok;
    }

    function constructOpPokeMessage(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) external view returns (bytes32) {
        return _constructOpPokeMessage(pokeData, schnorrData);
    }

    function _constructOpPokeMessage(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encodePacked(
                        wat,
                        abi.encodePacked(pokeData.val, pokeData.age),
                        abi.encodePacked(
                            schnorrData.signature,
                            schnorrData.commitment,
                            schnorrData.signersBlob
                        )
                    )
                )
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                           READ FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IScribe
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

    /// @inheritdoc IScribe
    function tryRead()
        external
        view
        virtual
        override(IScribe, Scribe)
        toll
        returns (bool, uint)
    {
        uint val = _currentVal();
        return (val != 0, val);
    }

    /// @inheritdoc IScribe
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

    /// @dev Returns the oracle's current value.
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

    /// @inheritdoc IScribeOptimistic
    function setOpChallengePeriod(uint16 opChallengePeriod_) external auth {
        _setOpChallengePeriod(opChallengePeriod_);
    }

    function _setOpChallengePeriod(uint16 opChallengePeriod_) private {
        require(opChallengePeriod_ != 0);

        if (opChallengePeriod != opChallengePeriod_) {
            emit OpChallengePeriodUpdated(
                msg.sender, opChallengePeriod, opChallengePeriod_
            );
            opChallengePeriod = opChallengePeriod_;
        }

        _afterAuthedAction();
    }

    /// @dev Overwritten from upstream contract to enforce _afterAuthedAction()
    ///      is executed after the initial function execution.
    function _drop(address caller, uint feedIndex) internal override(Scribe) {
        super._drop(caller, feedIndex);

        _afterAuthedAction();
    }

    /// @dev Overwritten from upstream contract to enforce _afterAuthedAction()
    ///      is executed after the initial function execution.
    function _setBar(uint8 bar_) internal override(Scribe) {
        super._setBar(bar_);

        _afterAuthedAction();
    }

    /// @dev Ensures an auth'ed configuration update does not enable
    ///      successfully challenging a prior to the update valid opPoke.
    function _afterAuthedAction() private {
        // Decide whether _opPokeData is finalized.
        bool opPokeDataFinalized =
            _opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // If _opPokeData is not finalized, drop it.
        //
        // Note that this ensures a valid opPoke cannot become invalid
        // after an auth'ed configuration change.
        if (!opPokeDataFinalized) {
            emit OpPokeDataDropped(msg.sender, _opPokeData.val, _opPokeData.age);
            delete _opPokeData;
        }

        // Set the age of contract's current value to block.timestamp.
        //
        // Note that this ensures an already signed, but now possibly invalid
        // with regards to contract configurations, opPoke payload cannot be
        // opPoke'd anymore.
        if (opPokeDataFinalized && _opPokeData.age > _pokeData.age) {
            _opPokeData.age = uint32(block.timestamp);
        } else {
            _pokeData.age = uint32(block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _rewardChallenger(address payable receiver) internal {
        uint bounty = address(this).balance;

        (bool ok, /*bytes memory data*/ ) = receiver.call{value: bounty}("");

        if (!ok) {
            // @todo Emit event?
        }
    }
}
