// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribeFactory} from "./IScribeFactory.sol";

import {Scribe} from "./Scribe.sol";
import {ScribeRouter} from "./ScribeRouter.sol";

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

/**
 * @title ScribeFactory
 * @custom:version 2.0.1
 *
 * @notice Factory contract to deploy Scribe and ScribeRouter oracle contracts
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract ScribeFactory is IScribeFactory, Auth, Toll {
    constructor(address initialAuthed) payable Auth(initialAuthed) {}

    /// @inheritdoc IScribeFactory
    function plantScribeWithRouter(
        ScribeConfig calldata scribeCfg,
        ScribeRouterConfig calldata routerCfg
    ) public toll returns (address, address) {
        Scribe scribe = _plantScribe(scribeCfg);
        ScribeRouter router = _plantRouter(routerCfg);

        scribe.kiss(address(router));
        router.setScribe(address(scribe));

        scribe.deny(address(this));
        router.deny(address(this));

        return (address(scribe), address(router));
    }

    /// @inheritdoc IScribeFactory
    function plantScribe(ScribeConfig calldata cfg)
        public
        toll
        returns (address)
    {
        Scribe scribe = _plantScribe(cfg);

        scribe.deny(address(this));

        return address(scribe);
    }

    /// @inheritdoc IScribeFactory
    function plantRouter(ScribeRouterConfig calldata cfg)
        public
        toll
        returns (address)
    {
        ScribeRouter router = _plantRouter(cfg);

        router.deny(address(this));

        return address(router);
    }

    // -- Internal Helpers --

    function _plantScribe(ScribeConfig calldata cfg) internal returns (Scribe) {
        // Deploy scribe.
        Scribe scribe = new Scribe(address(this), cfg.wat);
        emit ScribeDeployed(msg.sender, address(scribe), cfg.name);

        // Lift validators and set bar.
        scribe.lift(cfg.validators, cfg.registrationSigs);
        scribe.setBar(cfg.bar);

        // Rely authed and kiss tolled.
        for (uint i; i < cfg.authed.length; i++) {
            scribe.rely(cfg.authed[i]);
        }
        for (uint i; i < cfg.tolled.length; i++) {
            scribe.kiss(cfg.tolled[i]);
        }

        // Kiss zero address.
        scribe.kiss(address(0));

        return scribe;
    }

    function _plantRouter(ScribeRouterConfig calldata cfg)
        internal
        returns (ScribeRouter)
    {
        // Deploy router.
        ScribeRouter router = new ScribeRouter(address(this), cfg.name);
        emit ScribeRouterDeployed(msg.sender, address(router), cfg.name);

        // Rely authed and kiss tolled.
        for (uint i; i < cfg.authed.length; i++) {
            router.rely(cfg.authed[i]);
        }
        for (uint i; i < cfg.tolled.length; i++) {
            router.kiss(cfg.tolled[i]);
        }

        // Kiss zero address.
        router.kiss(address(0));

        return router;
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 */
contract ScribeFactory_COUNTER is ScribeFactory {
    // @todo           ^^^^^^^ Adjust counter of Factory instance.
    constructor(address initialAuthed) ScribeFactory(initialAuthed) {}
}
