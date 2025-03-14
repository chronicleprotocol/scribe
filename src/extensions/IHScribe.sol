// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IScribe} from "../IScribe.sol";

interface IHScribe is IScribe {
    /// @notice Returns the number of historical values the oracle serves.
    /// @dev This value is immutable and does not change during the contract's
    ///      lifetime.
    /// @return historySize_ The number of historical values the oracle serves.
    function historySize() external view returns (uint8 historySize_);

    /// @notice Returns the oracle's `past`th last value.
    /// @dev Reverts if:
    ///      - `past`th last value zero
    ///      - `past > historySize()`
    /// @dev Note that calling this function with `past = 0` is identical to
    ///      calling the IChronicle function `read()`.
    /// @param past The number of values in the past to read.
    /// @return value The `past`th last oracle value.
    function hRead(uint8 past) external view returns (uint value);

    /// @notice Returns the oracle's `past`th last value.
    /// @dev Reverts if:
    ///      - `past > historySize()`
    /// @dev Note that calling this function with `past = 0` is identical to
    ///      calling the IChronicle function `tryRead()`.
    /// @param past The number of values in the past to read.
    /// @return isValid True if `past`th last value exists, false otherwise
    /// @return value The `past`th last oracle value.
    function hTryRead(uint8 past)
        external
        view
        returns (bool isValid, uint value);

    /// @notice Returns the oracle's `past`th last value and its age.
    /// @dev Reverts if:
    ///      - `past`th last value zero
    ///      - `past > historySize()`
    /// @dev Note that calling this function with `past = 0` is identical to
    ///      calling the IChronicle function `readWithAge()`.
    /// @param past The number of values in the past to read.
    /// @return value The `past`th last oracle value.
    /// @return age The value's age.
    function hReadWithAge(uint8 past)
        external
        view
        returns (uint value, uint age);

    /// @notice Returns the oracle's `past`th last value and its age.
    /// @dev Reverts if:
    ///      - `past > historySize()`
    /// @dev Note that calling this function with `past = 0` is identical to
    ///      calling the IChronicle function `tryReadWithAge()`.
    /// @param past The number of values in the past to read.
    /// @return isValid True if `past`th last value exists, false otherwise
    /// @return value The `past`th last oracle value.
    /// @return age The value's age if value exists, zero otherwise.
    function hTryReadWithAge(uint8 past)
        external
        view
        returns (bool isValid, uint value, uint age);
}


