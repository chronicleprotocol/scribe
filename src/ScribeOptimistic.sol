pragma solidity ^0.8.16;

import {IScribeOptimistic} from "./IScribeOptimistic.sol";

import {IScribe} from "./IScribe.sol";
import {Scribe} from "./Scribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

/**
 * @title ScribeOptimistic
 *
 * @notice Schnorr multi-signature based optimistic Oracle providing onchain
 *         fault resolution
 */
contract ScribeOptimistic is IScribeOptimistic, Scribe {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];

    // -- Storage --

    /// @inheritdoc IScribeOptimistic
    uint16 public opChallengePeriod;

    /// @inheritdoc IScribeOptimistic
    uint8 public opFeedIndex;

    /// @dev The truncated hash of the schnorrData provided in last opPoke.
    ///      Binds the opFeed to their schnorrData.
    uint160 private _schnorrDataCommitment;

    /// @dev The age of the pokeData provided in last opPoke.
    ///      Ensures Schnorr signature can be verified after setting pokeData's
    ///      age to block.timestamp during opPoke.
    uint32 private _originalOpPokeDataAge;

    /// @dev opScribe's last opPoke'd value and corresponding age.
    PokeData private _opPokeData;

    /// @inheritdoc IScribeOptimistic
    uint public maxChallengeReward;

    // -- Constructor and Receive Functionality --

    constructor(bytes32 wat_) Scribe(wat_) {
        // Note to have a non-zero challenge period.
        _setOpChallengePeriod(1 hours);
    }

    receive() external payable {}

    // -- opPoke Functionality --

    /// @inheritdoc IScribeOptimistic
    function opPoke(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) external {
        _opPoke(pokeData, schnorrData, ecdsaData);
    }

    /// @dev Optimized function selector: 0x00000000.
    ///      Note that this function is _not_ defined via the IScribe interface
    ///      and one should _not_ depend on it.
    function opPoke_optimized_397084999(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) external payable {
        _opPoke(pokeData, schnorrData, ecdsaData);
    }

    function _opPoke(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) private {
        // Load _opPokeData from storage.
        PokeData memory opPokeData = _opPokeData;

        // Decide whether _opPokeData is finalized.
        bool opPokeDataFinalized =
            opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // Revert if _opPokeData is not finalized, i.e. still challengeable.
        if (!opPokeDataFinalized) {
            revert InChallengePeriod();
        }

        // Decide current age.
        uint32 age = opPokeDataFinalized && opPokeData.age > _pokeData.age
            ? opPokeData.age
            : _pokeData.age;

        // Revert if pokeData is stale.
        if (pokeData.age <= age) {
            revert StaleMessage(pokeData.age, age);
        }

        // Recover ECDSA signer.
        address signer = ecrecover(
            _constructOpPokeMessage(pokeData, schnorrData),
            ecdsaData.v,
            ecdsaData.r,
            ecdsaData.s
        );

        // Load signer's index.
        uint signerIndex = _feeds[signer];

        // Revert if signer is not feed.
        if (signerIndex == 0) {
            revert SignerNotFeed(signer);
        }

        // Store the signerIndex as opFeedIndex and bind them to their provided
        // schnorrData.
        opFeedIndex = uint8(signerIndex);
        _schnorrDataCommitment = uint160(
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
                        schnorrData.signersBlob
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
            emit OpPokeChallengedUnsuccessfully(msg.sender);

            // Decide whether _opPokeData stale already.
            bool opPokeDataStale = opPokeData.age <= _pokeData.age;

            // If _opPokeData is not stale, finalize it by moving it to the
            // _pokeData slot.
            if (!opPokeDataStale) {
                _pokeData = _opPokeData;
            }
        } else {
            emit OpPokeChallengedSuccessfully(msg.sender, err);

            // Drop opFeed and delete invalid _opPokeData.
            // Use address(this) as caller to indicate self-governed drop of
            // feed.
            _drop(address(this), opFeedIndex);

            // Pay reward to challenger.
            uint reward = challengeReward();
            if (_sendETH(payable(msg.sender), reward)) {
                emit OpChallengeRewardPaid(msg.sender, reward);
            }
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
    ) private view returns (bytes32) {
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

    // -- Toll'ed Read Functionality --

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
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
    /// @dev Only callable by toll'ed address.
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
    /// @dev Only callable by toll'ed address.
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

    // -- Auth'ed Functionality --

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

    function _drop(address caller, uint feedIndex) internal override(Scribe) {
        super._drop(caller, feedIndex);

        _afterAuthedAction();
    }

    function _setBar(uint8 bar_) internal override(Scribe) {
        super._setBar(bar_);

        _afterAuthedAction();
    }

    /// @dev Ensures an auth'ed configuration update does not enable
    ///      successfully challenging a prior to the update valid opPoke.
    function _afterAuthedAction() private {
        // Do nothing during deployment.
        if (address(this).code.length == 0) return;

        // Decide whether _opPokeData is finalized.
        bool opPokeDataFinalized =
            _opPokeData.age + opChallengePeriod <= uint32(block.timestamp);

        // If _opPokeData is not finalized, drop it.
        //
        // Note that this ensures a valid opPoke cannot become invalid
        // after an auth'ed configuration change.
        if (!opPokeDataFinalized) {
            emit OpPokeDataDropped(msg.sender, _opPokeData);
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

    // -- Searcher Incentivization Logic --

    /// @inheritdoc IScribeOptimistic
    function challengeReward() public view returns (uint) {
        uint balance = address(this).balance;
        return balance > maxChallengeReward ? maxChallengeReward : balance;
    }

    /// @inheritdoc IScribeOptimistic
    function setMaxChallengeReward(uint maxChallengeReward_) external auth {
        if (maxChallengeReward != maxChallengeReward_) {
            emit MaxChallengeRewardUpdated(
                msg.sender, maxChallengeReward, maxChallengeReward_
            );
            maxChallengeReward = maxChallengeReward_;
        }
    }

    function _sendETH(address payable to, uint amount) private returns (bool) {
        (bool ok,) = to.call{value: amount}("");
        return ok;
    }
}
