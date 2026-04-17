// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribeRouter} from "./IScribeRouter.sol";
import {IScribe} from "./IScribe.sol";

/**
 * @title ScribeRouter
 * @custom:version 2.0.1
 *
 * @notice A router contract for Scribe oracles
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract ScribeRouter is IScribeRouter, Auth, Toll {
    /// @inheritdoc IScribeRouter
    bytes32 public immutable wat;
    /// @inheritdoc IScribeRouter
    string public name;

    /// @inheritdoc IScribeRouter
    address public scribe;

    constructor(address initialAuthed, string memory name_)
        payable
        Auth(initialAuthed)
    {
        name = name_;
        wat = keccak256(bytes(name_));
    }

    /// @inheritdoc IScribeRouter
    function setScribe(address scribe_) external auth {
        if (scribe != scribe_) {
            emit ScribeUpdated(msg.sender, scribe, scribe_);
            scribe = scribe_;
        }
    }

    function _tryReadWithAge() internal view returns (bool, uint, uint) {
        return IScribe(scribe).tryReadWithAge();
    }

    // -- IChronicle --

    /// @inheritdoc IChronicle
    function read() external view toll returns (uint) {
        bool ok;
        uint val;
        (ok, val,) = _tryReadWithAge();
        require(ok);
        return val;
    }

    /// @inheritdoc IChronicle
    function tryRead() external view toll returns (bool, uint) {
        bool ok;
        uint val;
        (ok, val,) = _tryReadWithAge();
        return (ok, val);
    }

    /// @inheritdoc IChronicle
    function readWithAge() external view toll returns (uint, uint) {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = _tryReadWithAge();
        require(ok);
        return (val, age);
    }

    /// @inheritdoc IChronicle
    function tryReadWithAge() external view toll returns (bool, uint, uint) {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = _tryReadWithAge();
        return (ok, val, age);
    }

    // -- MakerDAO Compatibility --

    /// @inheritdoc IScribeRouter
    function peek() external view toll returns (uint, bool) {
        uint val;
        (, val,) = _tryReadWithAge();
        return (val, val != 0);
    }

    /// @inheritdoc IScribeRouter
    function peep() external view toll returns (uint, bool) {
        uint val;
        (, val,) = _tryReadWithAge();
        return (val, val != 0);
    }

    // -- Chainlink Compatibility --

    /// @inheritdoc IScribeRouter
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @inheritdoc IScribeRouter
    function latestRoundData()
        external
        view
        toll
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        )
    {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = _tryReadWithAge();

        roundId = 1;
        answer = int(val);
        // assert(uint(answer) == uint(val));
        startedAt = 0;
        updatedAt = age;
        answeredInRound = roundId;
    }

    /// @inheritdoc IScribeRouter
    function latestAnswer() external view toll returns (int) {
        uint val;
        (, val,) = _tryReadWithAge();
        return int(val);
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 */
contract ChronicleRouter_BASE_QUOTE_COUNTER is ScribeRouter {
    // @todo             ^^^^ ^^^^^ ^^^^^^^ Adjust name of Router instance.
    constructor(address initialAuthed, string memory name_)
        ScribeRouter(initialAuthed, name_)
    {}
}
