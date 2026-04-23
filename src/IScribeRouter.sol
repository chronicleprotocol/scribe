// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";

interface IScribeRouter is IChronicle {
    /// @notice Emitted when the scribe address is updated.
    /// @param caller The caller's address.
    /// @param oldScribe The old scribe address.
    /// @param newScribe The new scribe address.
    event ScribeUpdated(
        address indexed caller, address oldScribe, address newScribe
    );

    /// @notice Returns the name identifier.
    /// @return name The name of the oracle.
    function name() external view returns (string memory name);

    /// @notice Returns the wat identifier.
    /// @return wat The wat of the oracle.
    function wat() external view returns (bytes32 wat);

    /// @notice Returns the scribe address.
    /// @return scribe The scribe address.
    function scribe() external view returns (address scribe);

    /// @notice Updates the scribe contract.
    /// @dev Only callable by auth'ed address.
    /// @param scribe The scribe address.
    function setScribe(address scribe) external;

    // -- MakerDAO Compatibility --

    /// @notice Returns the oracle's current value.
    /// @custom:deprecated Use `tryRead()(bool,uint)` instead.
    /// @return value The oracle's current value if it exists, zero otherwise.
    /// @return isValid True if value exists, false otherwise.
    function peek() external view returns (uint value, bool isValid);

    /// @notice Returns the oracle's current value.
    /// @custom:deprecated Use `tryRead()(bool,uint)` instead.
    /// @return value The oracle's current value if it exists, zero otherwise.
    /// @return isValid True if value exists, false otherwise.
    function peep() external view returns (uint value, bool isValid);

    // -- Chainlink Compatibility --

    /// @notice Returns the number of decimals of the oracle's value.
    /// @dev Provides partial compatibility with Chainlink's
    ///      IAggregatorV3Interface.
    /// @return decimals The oracle value's number of decimals.
    function decimals() external view returns (uint8 decimals);

    /// @notice Returns the oracle's latest value.
    /// @dev Provides partial compatibility with Chainlink's
    ///      IAggregatorV3Interface.
    /// @return roundId 1.
    /// @return answer The oracle's latest value.
    /// @return startedAt 0.
    /// @return updatedAt The timestamp of oracle's latest update.
    /// @return answeredInRound 1.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        );

    /// @notice Returns the oracle's latest value.
    /// @dev Provides partial compatibility with Chainlink's
    ///      IAggregatorV3Interface.
    /// @custom:deprecated See https://docs.chain.link/data-feeds/api-reference/#latestanswer.
    /// @return answer The oracle's latest value.
    function latestAnswer() external view returns (int answer);
}
