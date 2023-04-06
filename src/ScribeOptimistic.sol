pragma solidity ^0.8.16;

import {IScribeOptimistic} from "./IScribeOptimistic.sol";

import {Scribe} from "./Scribe.sol";
import {IScribe} from "./IScribe.sol";

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
contract ScribeOptimistic is IScribeOptimistic, Scribe {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    /// @inheritdoc IScribeOptimistic
    uint16 public opChallengePeriod;

    /// @inheritdoc IScribeOptimistic
    address public opFeed;

    /// @inheritdoc IScribeOptimistic
    bytes32 public opCommitment;

    PokeData private _opPokeData;

    /*//////////////////////////////////////////////////////////////
                  CONSTRUCTOR & RECEIVE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // Note to have a non-zero challenge period.
        opChallengePeriod = 1 hours;
        emit OpChallengePeriodUpdated(msg.sender, 0, 1 hours);
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
        //       allocated one and don't just expand the memory.

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

    // @todo Should opChallenge return bool to indicate whether challenge
    //       succeeded?
    // @todo Remove pokeData argument?
    /// @inheritdoc IScribeOptimistic
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
        } else {
            // Drop opFeed and delete invalid _opPokeData.
            _drop(_feeds[opFeed]);

            // Pay challenge bounty to caller.
            _payChallengeBountyTo(payable(msg.sender));
        }
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
    function _drop(LibSecp256k1.Point memory pubKey)
        internal
        override(Scribe)
    {
        super._drop(pubKey);

        _afterAuthedAction();
    }

    /// @dev Overwritten from upstream contract to enforce _afterAuthedAction()
    ///      is executed after the initial function execution.
    function _drop(LibSecp256k1.Point[] memory pubKeys)
        internal
        override(Scribe)
    {
        super._drop(pubKeys);

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
        // Decide whether _opPokeData is finalized
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
        // Note that this ensures an already signed, but now possibly outdated
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

    // @todo Args as calldata? No need to abi.encode calldata.
    function _constructCommitment(
        PokeData memory pokeData,
        SchnorrSignatureData memory schnorrData
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                // @todo Packed problem??
                abi.encodePacked(schnorrData.signers),
                schnorrData.signature,
                schnorrData.commitment,
                wat
            )
        );
    }

    function _payChallengeBountyTo(address payable receiver) internal {
        // @todo Why again in assembly?
        assembly ("memory-safe") {
            // The bounty is the contract's ETH balance.
            let bounty := selfbalance()

            // Transfer the ETH and
            let callFailed := call(gas(), receiver, bounty, 0, 0, 0, 0)

            // Return if sending ETH failed.
            if callFailed { return(0, 0) }

            // @todo Emit log.
        }
    }
}
