// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IScribe} from "./IScribe.sol";

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

interface IScribeFactory {
    /// @dev ScribeConfig encapsulates a Scribe instance's deployment
    ///      configuration.
    struct ScribeConfig {
        string name;
        bytes32 wat;
        uint8 bar;
        address[] authed;
        address[] tolled;
        LibSecp256k1.Point[] validators;
        IScribe.ECDSAData[] registrationSigs;
    }

    /// @dev ScribeRouterConfig encapsulates a ScribeRouter instance's
    ///      deployment configuration.
    struct ScribeRouterConfig {
        string name;
        address[] authed;
        address[] tolled;
    }

    /// @notice Emitted when new Scribe instance deployed.
    /// @param caller The caller's address.
    /// @param scribe The deployed Scribe instance's address.
    /// @param name The Scribe instance's name.
    event ScribeDeployed(
        address indexed caller, address indexed scribe, string name
    );

    /// @notice Emitted when new ScribeRouter instance deployed.
    /// @param caller The caller's address.
    /// @param router The deployed ScribeRouter instance's address.
    /// @param name The ScribeRouter instance's name.
    event ScribeRouterDeployed(
        address indexed caller, address indexed router, string name
    );

    /// @notice Deploys a new Scribe and ScribeRouter instance.
    /// @dev Only callable by toll'ed address.
    /// @param scribeCfg The Scribe instance's deployment configuration.
    /// @param routerCfg The ScribeRouter instance's deployment configuration.
    /// @return The deployed Scribe instance's address.
    /// @return The deployed ScribeRouter instance's address.
    function plantScribeWithRouter(
        ScribeConfig calldata scribeCfg,
        ScribeRouterConfig calldata routerCfg
    ) external returns (address, address);

    /// @notice Deploys a new Scribe instance.
    /// @dev Only callable by toll'ed address.
    /// @param cfg The Scribe instance's deployment configuration.
    /// @return The deployed Scribe instance's address.
    function plantScribe(ScribeConfig calldata cfg) external returns (address);

    /// @notice Deploys a new ScribeRouter instance.
    /// @dev Only callable by toll'ed address.
    /// @param cfg The ScribeRouter instance's deployment configuration.
    /// @return The deployed ScribeRouter instance's address.
    function plantRouter(ScribeRouterConfig calldata cfg)
        external
        returns (address);
}
