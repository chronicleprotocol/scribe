// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeFactory} from "src/IScribeFactory.sol";
import {IScribeRouter} from "src/IScribeRouter.sol";
import {ScribeFactory} from "src/ScribeFactory.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

abstract contract IScribeFactoryTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;

    ScribeFactory private factory;

    // Events copied from IScribeFactory.
    event ScribeDeployed(
        address indexed caller, address indexed scribe, string name
    );
    event ScribeRouterDeployed(
        address indexed caller, address indexed router, string name
    );

    bytes32 constant FEED_REGISTRATION_MESSAGE = keccak256(
        abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256("Chronicle Feed Registration")
        )
    );

    function setUp(address factory_) internal virtual {
        factory = ScribeFactory(factory_);
        IToll(factory_).kiss(address(this));
    }

    // -- Helpers --

    function _makeFeeds(uint8 numberFeeds)
        internal
        returns (LibSecp256k1.Point[] memory, IScribe.ECDSAData[] memory)
    {
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](numberFeeds);
        IScribe.ECDSAData[] memory sigs = new IScribe.ECDSAData[](numberFeeds);

        // Note to not start with privKey=1. This is because the sum of public
        // keys would evaluate to:
        //   pubKeyOf(1) + pubKeyOf(2) + pubKeyOf(3) + ...
        // = pubKeyOf(3)               + pubKeyOf(3) + ...
        // Note that pubKeyOf(3) would be doubled. Doubling is not supported by
        // LibSecp256k1 as this would indicate a double-signing attack.
        uint privKey = 2;
        uint bloom;
        uint ctr;
        while (ctr != numberFeeds) {
            LibFeed.Feed memory feed = LibFeed.newFeed({privKey: privKey});

            // Check whether feed with id already created, if not create and
            // lift.
            if (bloom & (1 << feed.id) == 0) {
                bloom |= 1 << feed.id;

                pubKeys[ctr] = feed.pubKey;
                sigs[ctr] = feed.signECDSA(FEED_REGISTRATION_MESSAGE);
                ctr++;
            }

            privKey++;
        }

        return (pubKeys, sigs);
    }

    function _makeScribeConfig()
        internal
        returns (IScribeFactory.ScribeConfig memory cfg)
    {
        (
            LibSecp256k1.Point[] memory validators,
            IScribe.ECDSAData[] memory registrationSigs
        ) = _makeFeeds(2);

        address[] memory authed = new address[](1);
        authed[0] = address(this);

        address[] memory tolled = new address[](1);
        tolled[0] = address(this);

        cfg = IScribeFactory.ScribeConfig({
            name: "ETH/USD",
            wat: "ETH/USD",
            bar: 2,
            authed: authed,
            tolled: tolled,
            validators: validators,
            registrationSigs: registrationSigs
        });
    }

    function _makeRouterConfig()
        internal
        pure
        returns (IScribeFactory.ScribeRouterConfig memory cfg)
    {
        address[] memory authed = new address[](1);
        authed[0] = address(0xbeef);

        address[] memory tolled = new address[](1);
        tolled[0] = address(0xcafe);

        cfg = IScribeFactory.ScribeRouterConfig({
            name: "ETH/USD", authed: authed, tolled: tolled
        });
    }

    // -- Test: Deployment --

    function test_Deployment() public {
        assertTrue(IAuth(address(factory)).authed(address(this)));
    }

    // -- Test: plantScribe --

    function test_plantScribe() public {
        IScribeFactory.ScribeConfig memory cfg = _makeScribeConfig();

        vm.expectEmit(true, false, false, true);
        emit ScribeDeployed(address(this), address(0), cfg.name);

        address scribe = factory.plantScribe(cfg);
        assertNotEq(scribe.code.length, 0);

        // Wat set.
        assertEq(IScribe(scribe).wat(), cfg.wat);

        // Feeds lifted and bar set.
        for (uint i; i < cfg.validators.length; i++) {
            assertTrue(IScribe(scribe).feeds(cfg.validators[i].toAddress()));
        }
        assertEq(IScribe(scribe).bar(), cfg.bar);

        // Expected addresses authed and tolled.
        for (uint i; i < cfg.authed.length; i++) {
            assertTrue(IAuth(scribe).authed(cfg.authed[i]));
        }
        for (uint i; i < cfg.tolled.length; i++) {
            assertTrue(IToll(scribe).tolled(cfg.tolled[i]));
        }

        // Zero address tolled.
        assertTrue(IToll(scribe).tolled(address(0)));

        // Factory denied.
        assertFalse(IAuth(scribe).authed(address(factory)));
    }

    // -- Test: plantRouter --

    function test_plantRouter() public {
        IScribeFactory.ScribeRouterConfig memory cfg = _makeRouterConfig();

        vm.expectEmit(true, false, false, true);
        emit ScribeRouterDeployed(address(this), address(0), cfg.name);

        address router = factory.plantRouter(cfg);
        assertNotEq(router.code.length, 0);

        // Name set.
        assertEq(IScribeRouter(router).name(), cfg.name);

        // Expected addresses authed and tolled.
        for (uint i; i < cfg.authed.length; i++) {
            assertTrue(IAuth(router).authed(cfg.authed[i]));
        }
        for (uint i; i < cfg.tolled.length; i++) {
            assertTrue(IToll(router).tolled(cfg.tolled[i]));
        }

        // Zero address tolled.
        assertTrue(IToll(router).tolled(address(0)));

        // Factory denied.
        assertFalse(IAuth(router).authed(address(factory)));

        // Scribe not set.
        assertEq(IScribeRouter(router).scribe(), address(0));
    }

    // -- Test: plantScribeWithRouter --

    function test_plantScribeWithRouter() public {
        IScribeFactory.ScribeConfig memory scribeCfg = _makeScribeConfig();
        IScribeFactory.ScribeRouterConfig memory routerCfg = _makeRouterConfig();

        (address scribe, address router) =
            factory.plantScribeWithRouter(scribeCfg, routerCfg);
        assertNotEq(scribe.code.length, 0);
        assertNotEq(router.code.length, 0);

        // Scribe set on router and router tolled on scribe.
        assertEq(IScribeRouter(router).scribe(), scribe);
        assertTrue(IToll(scribe).tolled(router));

        // -- Scribe Checks

        // Wat set.
        assertEq(IScribe(scribe).wat(), scribeCfg.wat);

        // Feeds lifted and bar set.
        for (uint i; i < scribeCfg.validators.length; i++) {
            assertTrue(
                IScribe(scribe).feeds(scribeCfg.validators[i].toAddress())
            );
        }
        assertEq(IScribe(scribe).bar(), scribeCfg.bar);

        // Expected addresses authed and tolled.
        for (uint i; i < scribeCfg.authed.length; i++) {
            assertTrue(IAuth(scribe).authed(scribeCfg.authed[i]));
        }
        for (uint i; i < scribeCfg.tolled.length; i++) {
            assertTrue(IToll(scribe).tolled(scribeCfg.tolled[i]));
        }

        // Zero address tolled.
        assertTrue(IToll(scribe).tolled(address(0)));

        // Factory denied.
        assertFalse(IAuth(scribe).authed(address(factory)));

        // -- ScribeRouter Checks

        // Name set.
        assertEq(IScribeRouter(router).name(), routerCfg.name);

        // Expected addresses authed and tolled.
        for (uint i; i < routerCfg.authed.length; i++) {
            assertTrue(IAuth(router).authed(routerCfg.authed[i]));
        }
        for (uint i; i < routerCfg.tolled.length; i++) {
            assertTrue(IToll(router).tolled(routerCfg.tolled[i]));
        }

        // Zero address tolled.
        assertTrue(IToll(router).tolled(address(0)));

        // Factory denied.
        assertFalse(IAuth(router).authed(address(factory)));
    }

    // -- Test: Toll Protection --

    function test_plantScribe_isTollProtected() public {
        IScribeFactory.ScribeConfig memory cfg = _makeScribeConfig();

        vm.prank(address(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xdead))
        );
        factory.plantScribe(cfg);
    }

    function test_plantRouter_isTollProtected() public {
        IScribeFactory.ScribeRouterConfig memory cfg = _makeRouterConfig();

        vm.prank(address(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xdead))
        );
        factory.plantRouter(cfg);
    }

    function test_plantScribeWithRouter_isTollProtected() public {
        IScribeFactory.ScribeConfig memory scribeCfg = _makeScribeConfig();
        IScribeFactory.ScribeRouterConfig memory routerCfg = _makeRouterConfig();

        vm.prank(address(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xdead))
        );
        factory.plantScribeWithRouter(scribeCfg, routerCfg);
    }
}
