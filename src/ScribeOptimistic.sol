// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";

import {IScribeOptimistic} from "./IScribeOptimistic.sol";

import {IScribe} from "./IScribe.sol";
import {Scribe} from "./Scribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

/**
 * @title ScribeOptimistic
 *
 * @notice Scribe based optimistic Oracle with onchain fault resolution
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract ScribeOptimistic is IScribeOptimistic, Scribe {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    // -- Storage --

    /// @inheritdoc IScribeOptimistic
    uint16 public opChallengePeriod;

    /// @inheritdoc IScribeOptimistic
    uint8 public opFeedId;

    /// @dev The truncated hash of the schnorrData provided in last opPoke.
    ///      Binds the opFeed to their schnorrData.
    uint160 internal _schnorrDataCommitment;

    /// @dev The age of the pokeData provided in last opPoke.
    ///      Ensures Schnorr signature can be verified after setting pokeData's
    ///      age to block.timestamp during opPoke.
    uint32 internal _originalOpPokeDataAge;

    /// @dev opScribe's last opPoke'd value and corresponding age.
    PokeData internal _opPokeData;

    /// @inheritdoc IScribeOptimistic
    uint public maxChallengeReward;

    // -- Constructor and Receive Functionality --

    constructor(address initialAuthed, bytes32 wat_)
        payable
        Scribe(initialAuthed, wat_)
    {
        // Note to have a non-zero challenge period.
        _setOpChallengePeriod(20 minutes);

        // Set maxChallengeReward to type(uint).max.
        _setMaxChallengeRewards(type(uint).max);
    }

    receive() external payable {}

    // -- Poke Functionality --

    function _poke(PokeData calldata pokeData, SchnorrData calldata schnorrData)
        internal
        override(Scribe)
    {
        // Load current age from storage.
        uint32 age = _currentPokeData().age;

        // Revert if pokeData stale.
        if (pokeData.age <= age) {
            revert StaleMessage(pokeData.age, age);
        }
        // Revert if pokeData from the future.
        if (pokeData.age > uint32(block.timestamp)) {
            revert FutureMessage(pokeData.age, uint32(block.timestamp));
        }

        // Revert if schnorrData does not prove integrity of pokeData.
        bool ok;
        bytes memory err;
        // forgefmt: disable-next-item
        (ok, err) = _verifySchnorrSignature(
            constructPokeMessage(pokeData),
            schnorrData
        );
        if (!ok) {
            _revert(err);
        }

        // Store pokeData's val in _pokeData storage and set its age to now.
        _pokeData.val = pokeData.val;
        _pokeData.age = uint32(block.timestamp);

        emit Poked(msg.sender, pokeData.val, pokeData.age);
    }

    // -- opPoke Functionality --

    /// @dev Optimized function selector: 0x00000000.
    ///      Note that this function is _not_ defined via the IScribeOptimistic
    ///      interface and one should _not_ depend on it.
    function opPoke_optimized_397084999(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) external payable {
        _opPoke(pokeData, schnorrData, ecdsaData);
    }

    /// @inheritdoc IScribeOptimistic
    function opPoke(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) external {
        _opPoke(pokeData, schnorrData, ecdsaData);
    }

    function _opPoke(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) internal {
        // Revert if schnorrData.feedIds' length is higher than bar's maximum
        // value.
        //
        // Note that this prevents opPoke's with such big schnorrData that it
        // becomes economically unprofitable to challenge them.
        if (schnorrData.feedIds.length > type(uint8).max) {
            revert BarNotReached(type(uint8).max, bar);
        }

        // Load _opPokeData from storage.
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData finalized.
        bool opPokeDataFinalized =
            opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // Revert if _opPokeData not finalized, i.e. still challengeable.
        if (!opPokeDataFinalized) {
            revert InChallengePeriod();
        }

        // Decide current age.
        uint32 age =
            opPokeData.age > _pokeData.age ? opPokeData.age : _pokeData.age;

        // Revert if pokeData stale.
        if (pokeData.age <= age) {
            revert StaleMessage(pokeData.age, age);
        }
        // Revert if pokeData from the future.
        if (pokeData.age > uint32(block.timestamp)) {
            revert FutureMessage(pokeData.age, uint32(block.timestamp));
        }

        // Recover ECDSA signer.
        address signer = ecrecover(
            _constructOpPokeMessage(pokeData, schnorrData),
            ecdsaData.v,
            ecdsaData.r,
            ecdsaData.s
        );

        // Compute feed id of signer.
        uint8 feedId = uint8(uint(uint160(signer)) >> 152);

        // Revert if signer not feed.
        // assert(_pubKeys[feedId].toAddress() != address(0));
        if (_pubKeys[feedId].toAddress() != signer) {
            revert SignerNotFeed(signer);
        }

        // Store the feed's id as opFeedId and bind them to their provided
        // schnorrData.
        opFeedId = feedId;
        _schnorrDataCommitment = uint160(
            uint(
                keccak256(
                    abi.encodePacked(
                        schnorrData.signature,
                        schnorrData.commitment,
                        schnorrData.feedIds
                    )
                )
            )
        );

        // If _opPokeData provides the current val, move it to the _pokeData
        // storage to free _opPokeData storage. If the current val is provided
        // by _pokeData, _opPokeData can be overwritten.
        if (opPokeData.age == age) {
            _pokeData = opPokeData;
        }

        // Store provided pokeData's val in _opPokeData storage.
        _opPokeData.val = pokeData.val;
        _opPokeData.age = uint32(block.timestamp);

        // Store pokeData's age to allow recreating original pokeMessage.
        _originalOpPokeDataAge = pokeData.age;

        emit OpPoked(msg.sender, signer, schnorrData, pokeData);
    }

    /// @inheritdoc IScribeOptimistic
    function opChallenge(SchnorrData calldata schnorrData)
        external
        returns (bool)
    {
        // Load _opPokeData from storage.
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is challengeable.
        bool opPokeDataChallengeable =
            opPokeData.age + opChallengePeriod > uint32(block.timestamp);

        // Revert if _opPokeData is not challengeable.
        if (!opPokeDataChallengeable) {
            revert NoOpPokeToChallenge();
        }

        // Construct truncated hash from schnorrData.
        uint160 schnorrDataHash = uint160(
            uint(
                keccak256(
                    abi.encodePacked(
                        schnorrData.signature,
                        schnorrData.commitment,
                        schnorrData.feedIds
                    )
                )
            )
        );

        // Revert if schnorrDataHash does not match _schnorrDataCommitment.
        if (schnorrDataHash != _schnorrDataCommitment) {
            revert SchnorrDataMismatch(schnorrDataHash, _schnorrDataCommitment);
        }

        // Decide whether schnorrData verifies opPokeData.
        bool ok;
        bytes memory err;
        (ok, err) = _verifySchnorrSignature(
            constructPokeMessage(
                PokeData({val: opPokeData.val, age: _originalOpPokeDataAge})
            ),
            schnorrData
        );

        if (ok) {
            // Decide whether _opPokeData stale already.
            bool opPokeDataStale = opPokeData.age <= _pokeData.age;

            // If _opPokeData not stale, finalize it by moving it to the
            // _pokeData storage. Note to also clean the _opPokeData storage to
            // not block new opPoke's as _opPokeData's challenge period not over.
            if (!opPokeDataStale) {
                _pokeData = _opPokeData;
                delete _opPokeData;
            }

            emit OpPokeChallengedUnsuccessfully(msg.sender, schnorrData);
        } else {
            // Drop opFeed and delete invalid _opPokeData.
            // Note to use address(this) as caller to indicate self-governed
            // drop of feed.
            _drop(address(this), opFeedId);

            // Pay ETH reward to challenger.
            uint reward = challengeReward();
            if (_sendETH(payable(msg.sender), reward)) {
                emit OpChallengeRewardPaid(msg.sender, schnorrData, reward);
            }

            emit OpPokeChallengedSuccessfully(msg.sender, schnorrData, err);
        }

        // Return whether challenging was successful.
        return !ok;
    }

    /// @inheritdoc IScribeOptimistic
    function constructOpPokeMessage(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData
    ) external view returns (bytes32) {
        return _constructOpPokeMessage(pokeData, schnorrData);
    }

    function _constructOpPokeMessage(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encodePacked(
                        wat,
                        pokeData.val,
                        pokeData.age,
                        schnorrData.signature,
                        schnorrData.commitment,
                        schnorrData.feedIds
                    )
                )
            )
        );
    }

    // -- Toll'ed Read Functionality --

    // - IChronicle Functions

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function read()
        external
        view
        override(IChronicle, Scribe)
        toll
        returns (uint)
    {
        uint val = _currentPokeData().val;
        require(val != 0);
        return val;
    }

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function tryRead()
        external
        view
        override(IChronicle, Scribe)
        toll
        returns (bool, uint)
    {
        uint val = _currentPokeData().val;
        return (val != 0, val);
    }

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function readWithAge()
        external
        view
        override(IChronicle, Scribe)
        toll
        returns (uint, uint)
    {
        PokeData memory pokeData = _currentPokeData();
        require(pokeData.val != 0);
        return (pokeData.val, pokeData.age);
    }

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function tryReadWithAge()
        external
        view
        override(IChronicle, Scribe)
        toll
        returns (bool, uint, uint)
    {
        PokeData memory pokeData = _currentPokeData();
        return pokeData.val != 0
            ? (true, pokeData.val, pokeData.age)
            : (false, 0, 0);
    }

    // - MakerDAO Compatibility

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function peek()
        external
        view
        override(IScribe, Scribe)
        toll
        returns (uint, bool)
    {
        uint val = _currentPokeData().val;
        return (val, val != 0);
    }

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function peep()
        external
        view
        override(IScribe, Scribe)
        toll
        returns (uint, bool)
    {
        uint val = _currentPokeData().val;
        return (val, val != 0);
    }

    // - Chainlink Compatibility

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function latestRoundData()
        external
        view
        override(IScribe, Scribe)
        toll
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        )
    {
        PokeData memory pokeData = _currentPokeData();

        roundId = 1;
        answer = int(uint(pokeData.val));
        // assert(uint(answer) == uint(pokeData.val));
        startedAt = 0;
        updatedAt = pokeData.age;
        answeredInRound = roundId;
    }

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function latestAnswer()
        external
        view
        virtual
        override(IScribe, Scribe)
        toll
        returns (int)
    {
        uint val = _currentPokeData().val;
        return int(val);
    }

    function _currentPokeData() internal view returns (PokeData memory) {
        // Load pokeData slots from storage.
        PokeData memory pokeData = _pokeData;
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is finalized.
        bool opPokeDataFinalized =
            opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // Decide and return current pokeData.
        if (opPokeDataFinalized && opPokeData.age > pokeData.age) {
            return opPokeData;
        } else {
            return pokeData;
        }
    }

    // -- Auth'ed Functionality --

    /// @inheritdoc IScribeOptimistic
    function setOpChallengePeriod(uint16 opChallengePeriod_) external auth {
        _setOpChallengePeriod(opChallengePeriod_);
    }

    function _setOpChallengePeriod(uint16 opChallengePeriod_) internal {
        require(opChallengePeriod_ != 0);

        if (opChallengePeriod != opChallengePeriod_) {
            emit OpChallengePeriodUpdated(
                msg.sender, opChallengePeriod, opChallengePeriod_
            );
            opChallengePeriod = opChallengePeriod_;
        }

        _afterAuthedAction();
    }

    function _drop(address caller, uint8 feedId) internal override(Scribe) {
        super._drop(caller, feedId);

        _afterAuthedAction();
    }

    function _setBar(uint8 bar_) internal override(Scribe) {
        super._setBar(bar_);

        _afterAuthedAction();
    }

    /// @dev Ensures an auth'ed configuration update does not enable
    ///      successfully challenging a prior to the update valid opPoke.
    ///
    /// @custom:invariant Val is provided if _pokeData prior to the tx is
    ///                   non-empty. Note that this is the case if there were
    ///                   at least two valid calls ∊ {poke, opPoke}.
    ///                     preTx(_pokeData) != (0, 0)
    ///                       → (true, _) = postTx(tryRead())
    /// @custom:invariant Val is provided via _pokeData after the tx.
    ///                     postTx(readWithAge()) = postTx(_pokeData)
    /// @custom:invariant _opPokeData is empty after the tx.
    ///                     (0, 0) = postTx(_opPokeData)
    function _afterAuthedAction() internal {
        // Do nothing during deployment.
        if (address(this).code.length == 0) return;

        // Load _opPokeData from storage.
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is finalized.
        //
        // Note that the decision is based on the possibly updated
        // opChallengePeriod! This means a once finalized opPoke may be dropped
        // if the opChallengePeriod was increased.
        bool opPokeDataFinalized =
            opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // Note that _opPokeData is in one of the following three states:
        // 1. finalized and newer than _pokeData
        // 2. finalized but older than _pokeData
        // 3. non-finalized
        //
        // Note that for state 1 _opPokeData can be moved to _pokeData and
        // afterwards deleted.
        // Note that for state 2 and 3 _opPokeData can be directly deleted.

        // If _opPokeData is in state 1, move it to the _pokeData storage.
        //
        // Note that this ensures the current value is provided via _pokeData.
        if (opPokeDataFinalized && opPokeData.age > _pokeData.age) {
            _pokeData = opPokeData;
        }

        // If _opPokeData is in state 3, emit event to indicate a possibly valid
        // opPoke was dropped.
        if (!opPokeDataFinalized) {
            emit OpPokeDataDropped(msg.sender, opPokeData);
        }

        // Now it is safe to delete _opPokeData.
        delete _opPokeData;

        // Note that the current value is now provided via _pokeData.
        // assert(_currentPokeData().val == _pokeData.val);
        // assert(_currentPokeData().age == _pokeData.age);

        // Set the age of contract's current value to block.timestamp.
        //
        // Note that this ensures an already signed, but now possibly invalid
        // with regards to contract configurations, opPoke payload cannot be
        // opPoke'd anymore.
        _pokeData.age = uint32(block.timestamp);
    }

    // -- Searcher Incentivization Logic --

    /// @inheritdoc IScribeOptimistic
    function challengeReward() public view returns (uint) {
        uint balance = address(this).balance;
        return balance > maxChallengeReward ? maxChallengeReward : balance;
    }

    /// @inheritdoc IScribeOptimistic
    function setMaxChallengeReward(uint maxChallengeReward_) external auth {
        _setMaxChallengeRewards(maxChallengeReward_);
    }

    function _setMaxChallengeRewards(uint maxChallengeReward_) internal {
        if (maxChallengeReward != maxChallengeReward_) {
            emit MaxChallengeRewardUpdated(
                msg.sender, maxChallengeReward, maxChallengeReward_
            );
            maxChallengeReward = maxChallengeReward_;
        }
    }

    function _sendETH(address payable to, uint amount)
        internal
        returns (bool)
    {
        (bool ok,) = to.call{value: amount}("");
        return ok;
    }
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 *
 *      For more info, see docs/Deployment.md.
 */
contract Chronicle_BASE_QUOTE_COUNTER is ScribeOptimistic {
    // @todo       ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.
    constructor(address initialAuthed, bytes32 wat_)
        ScribeOptimistic(initialAuthed, wat_)
    {}
}
