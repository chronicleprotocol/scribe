// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {Scribe} from "src/Scribe.sol";
import {IScribe} from "src/IScribe.sol";

import {IScribeRouter} from "src/IScribeRouter.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

abstract contract IScribeRouterTest is Test {
    using LibFeed for LibFeed.Feed;
    using LibFeed for LibFeed.Feed[];

    IScribeRouter private router;
    IScribe private scribe;

    // Events copied from IScribeRouter.
    event ScribeUpdated(
        address indexed caller, address oldScribe, address newScribe
    );

    function setUp(address router_) internal virtual {
        // Set router and toll address(this).
        router = IScribeRouter(router_);
        IToll(address(router)).kiss(address(this));

        // Deploy scribe and toll router and address(this).
        scribe = new Scribe(address(this), "ETH/USD");
        IToll(address(scribe)).kiss(address(router));
        IToll(address(scribe)).kiss(address(this));

        // Set scribe on router.
        router.setScribe(address(scribe));
    }

    function _liftFeeds(uint8 numberFeeds)
        internal
        returns (LibFeed.Feed[] memory)
    {
        LibFeed.Feed[] memory feeds = new LibFeed.Feed[](uint(numberFeeds));

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

                feeds[ctr++] = feed;
                scribe.lift(
                    feed.pubKey,
                    feed.signECDSA(scribe.feedRegistrationMessage())
                );
            }

            privKey++;
        }

        return feeds;
    }

    function _poke(uint128 val) internal {
        LibFeed.Feed[] memory feeds = _liftFeeds(scribe.bar());

        IScribe.PokeData memory pokeData;
        pokeData.val = val;
        pokeData.age = uint32(block.timestamp);

        IScribe.SchnorrData memory schnorrData;
        schnorrData = feeds.signSchnorr(scribe.constructPokeMessage(pokeData));

        scribe.poke(pokeData, schnorrData);
    }

    function _checkReadFunctions(uint wantVal, uint wantAge) internal {
        bool ok;
        uint gotVal;
        uint gotAge;

        assertEq(router.read(), wantVal);
        assertEq(scribe.read(), wantVal);

        (ok, gotVal) = router.tryRead();
        assertEq(gotVal, wantVal);
        assertTrue(ok);
        (ok, gotVal) = scribe.tryRead();
        assertEq(gotVal, wantVal);
        assertTrue(ok);

        (gotVal, gotAge) = router.readWithAge();
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);
        (gotVal, gotAge) = scribe.readWithAge();
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);

        (ok, gotVal, gotAge) = router.tryReadWithAge();
        assertTrue(ok);
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);
        (ok, gotVal, gotAge) = scribe.tryReadWithAge();
        assertTrue(ok);
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);

        (gotVal, ok) = router.peek();
        assertEq(gotVal, wantVal);
        assertTrue(ok);
        (gotVal, ok) = scribe.peek();
        assertEq(gotVal, wantVal);
        assertTrue(ok);

        (gotVal, ok) = router.peep();
        assertEq(gotVal, wantVal);
        assertTrue(ok);
        (gotVal, ok) = scribe.peep();
        assertEq(gotVal, wantVal);
        assertTrue(ok);

        uint80 roundId;
        int answer;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            router.latestRoundData();
        assertEq(uint(roundId), 1);
        assertEq(uint(answer), wantVal);
        assertEq(startedAt, 0);
        assertEq(updatedAt, wantAge);
        assertEq(uint(answeredInRound), 1);
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            scribe.latestRoundData();
        assertEq(uint(roundId), 1);
        assertEq(uint(answer), wantVal);
        assertEq(startedAt, 0);
        assertEq(updatedAt, wantAge);
        assertEq(uint(answeredInRound), 1);

        answer = router.latestAnswer();
        assertEq(uint(answer), wantVal);
        answer = scribe.latestAnswer();
        assertEq(uint(answer), wantVal);
    }

    // -- Test: Deployment --

    function test_Deployment() public {
        // Address given as constructor argument is auth'ed.
        assertTrue(IAuth(address(router)).authed(address(this)));

        // Name and wat are set.
        assertEq(router.name(), "ETH/USD");
        assertEq(router.wat(), keccak256(bytes("ETH/USD")));
    }

    // -- Test: setScribe --

    function testFuzz_setScribe(address newScribe) public {
        address current = router.scribe();
        if (current != newScribe) {
            vm.expectEmit();
            emit ScribeUpdated(address(this), current, newScribe);
        }

        router.setScribe(newScribe);
        assertEq(router.scribe(), newScribe);
    }

    function test_setScribe_isAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        router.setScribe(address(0));
    }

    // -- Test: Read Functions --

    function testFuzz_readFunctions(uint128 val) public {
        vm.assume(val != 0);
        _poke(val);
        _checkReadFunctions(val, block.timestamp);
    }

    function test_readFunctions_ValZero() public {
        bool ok;
        uint gotVal;
        uint gotAge;

        // read() reverts.
        vm.expectRevert();
        router.read();
        vm.expectRevert();
        scribe.read();

        // tryRead() returns (false, 0).
        (ok, gotVal) = router.tryRead();
        assertFalse(ok);
        assertEq(gotVal, 0);
        (ok, gotVal) = scribe.tryRead();
        assertFalse(ok);
        assertEq(gotVal, 0);

        // readWithAge() reverts.
        vm.expectRevert();
        router.readWithAge();
        vm.expectRevert();
        scribe.readWithAge();

        // tryReadWithAge() returns (false, 0, 0).
        (ok, gotVal, gotAge) = router.tryReadWithAge();
        assertFalse(ok);
        assertEq(gotVal, 0);
        assertEq(gotAge, 0);
        (ok, gotVal, gotAge) = scribe.tryReadWithAge();
        assertFalse(ok);
        assertEq(gotVal, 0);
        assertEq(gotAge, 0);

        // peek() returns (0, false).
        (gotVal, ok) = router.peek();
        assertEq(gotVal, 0);
        assertFalse(ok);
        (gotVal, ok) = scribe.peek();
        assertEq(gotVal, 0);
        assertFalse(ok);

        // peep() returns (0, false).
        (gotVal, ok) = router.peep();
        assertEq(gotVal, 0);
        assertFalse(ok);
        (gotVal, ok) = scribe.peep();
        assertEq(gotVal, 0);
        assertFalse(ok);

        // latestRoundData() returns (1, 0, 0, 0, 1).
        uint80 roundId;
        int answer;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            router.latestRoundData();
        assertEq(uint(roundId), 1);
        assertEq(uint(answer), 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(uint(answeredInRound), 1);
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            scribe.latestRoundData();
        assertEq(uint(roundId), 1);
        assertEq(uint(answer), 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(uint(answeredInRound), 1);

        // latestAnswer() returns 0.
        answer = router.latestAnswer();
        assertEq(uint(answer), 0);
        answer = scribe.latestAnswer();
        assertEq(uint(answer), 0);
    }

    // -- Test: decimals --

    function test_decimals() public {
        assertEq(router.decimals(), 18);
    }

    // -- Test: Toll Protected Functions --

    // - IChronicle Functions

    function test_read_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.read();
    }

    function test_tryRead_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.tryRead();
    }

    function test_readWithAge_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.readWithAge();
    }

    function test_tryReadWithAge_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.tryReadWithAge();
    }

    // - MakerDAO Compatibility

    function test_peek_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.peek();
    }

    function test_peep_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.peep();
    }

    // - Chainlink Compatibility

    function test_latestRoundData_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.latestRoundData();
    }

    function test_latestAnswer_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        router.latestAnswer();
    }
}

