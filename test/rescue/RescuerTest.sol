// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";

import {Rescuer} from "script/rescue/Rescuer.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";
import {ScribeOptimistic} from "src/ScribeOptimistic.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {LibFeed} from "script/libs/LibFeed.sol";

contract RescuerTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibFeed for LibFeed.Feed;

    // Events copied from Rescuer.
    event Recovered(
        address indexed caller, address indexed opScribe, uint amount
    );
    event Withdrawed(
        address indexed caller, address indexed receiver, uint amount
    );

    Rescuer private rescuer;
    IScribeOptimistic private opScribe;

    bytes32 internal FEED_REGISTRATION_MESSAGE;

    function setUp() public {
        opScribe = new ScribeOptimistic(address(this), bytes32("TEST/TEST"));

        rescuer = new Rescuer(address(this));

        // Note to auth rescuer on opScribe.
        IAuth(address(opScribe)).rely(address(rescuer));

        // Note to let opScribe have a non-zero ETH balance.
        vm.deal(address(opScribe), 1 ether);

        // Cache constants.
        FEED_REGISTRATION_MESSAGE = opScribe.feedRegistrationMessage();
    }

    // -- Test: Suck --

    function testFuzz_suck(uint privKeySeed) public {
        // Create new feed from privKeySeed.
        LibFeed.Feed memory feed =
            LibFeed.newFeed(_bound(privKeySeed, 1, LibSecp256k1.Q() - 1));

        // Construct opPoke signature with invalid Schnorr signature.
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig =
            _constructOpPokeSig(feed, pokeDataAge);

        vm.expectEmit();
        emit Recovered(address(this), address(opScribe), 1 ether);

        rescuer.suck(
            address(opScribe),
            feed.pubKey,
            feed.signECDSA(FEED_REGISTRATION_MESSAGE),
            pokeDataAge,
            opPokeSig
        );

        // Verify balances.
        assertEq(address(opScribe).balance, 0);
        assertEq(address(rescuer).balance, 1 ether);

        // Verify feed got kicked.
        assertFalse(opScribe.feeds(feed.pubKey.toAddress()));
    }

    function testFuzz_suck_FailsIf_RescuerNotAuthedOnOpScribe(uint privKeySeed)
        public
    {
        // Create new feed from privKeySeed.
        LibFeed.Feed memory feed =
            LibFeed.newFeed(_bound(privKeySeed, 1, LibSecp256k1.Q() - 1));

        // Construct opPoke signature with invalid Schnorr signature.
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig =
            _constructOpPokeSig(feed, pokeDataAge);

        // Deny rescuer on opScribe.
        IAuth(address(opScribe)).deny(address(rescuer));

        // Expect rescue to fail.
        vm.expectRevert();
        rescuer.suck(
            address(opScribe),
            feed.pubKey,
            feed.signECDSA(FEED_REGISTRATION_MESSAGE),
            pokeDataAge,
            opPokeSig
        );
    }

    function testFuzz_suck_FailsIf_OpScribeNotDeactivated(
        uint privKeySeed,
        uint privKeyLiftedSeed
    ) public {
        // Create new feeds from seeds
        LibFeed.Feed memory feed =
            LibFeed.newFeed(_bound(privKeySeed, 1, LibSecp256k1.Q() - 1));
        LibFeed.Feed memory feedLifted =
            LibFeed.newFeed(_bound(privKeyLiftedSeed, 1, LibSecp256k1.Q() - 1));

        // Lift feedLifted.
        opScribe.lift(
            feedLifted.pubKey,
            feedLifted.signECDSA(opScribe.feedRegistrationMessage())
        );

        // Construct opPoke signature with invalid Schnorr signature.
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig =
            _constructOpPokeSig(feed, pokeDataAge);

        // Expect rescue to fail.
        vm.expectRevert();
        rescuer.suck(
            address(opScribe),
            feed.pubKey,
            feed.signECDSA(FEED_REGISTRATION_MESSAGE),
            pokeDataAge,
            opPokeSig
        );
    }

    function test_suck_isAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        rescuer.suck(
            address(opScribe),
            LibSecp256k1.ZERO_POINT(),
            IScribe.ECDSAData(uint8(0), bytes32(0), bytes32(0)),
            uint32(0),
            IScribe.ECDSAData(uint8(0), bytes32(0), bytes32(0))
        );
    }

    // -- Test: Withdraw --

    function testFuzz_withdraw_ToEOA(
        address payable receiver,
        uint balance,
        uint withdrawal
    ) public {
        vm.assume(receiver.code.length == 0);
        vm.assume(balance >= withdrawal);

        // Let rescuer have ETH balance.
        vm.deal(address(rescuer), balance);

        vm.expectEmit();
        emit Withdrawed(address(this), receiver, withdrawal);

        rescuer.withdraw(receiver, withdrawal);

        assertEq(address(rescuer).balance, balance - withdrawal);
        assertEq(receiver.balance, withdrawal);
    }

    function test_withdraw_ToContract(uint balance, uint withdrawal) public {
        vm.assume(balance >= withdrawal);

        // Let rescuer have ETH balance.
        vm.deal(address(rescuer), balance);

        // Deploy ETH receiver.
        ETHReceiver receiver = new ETHReceiver();

        vm.expectEmit();
        emit Withdrawed(address(this), address(receiver), withdrawal);

        rescuer.withdraw(payable(address(receiver)), withdrawal);

        assertEq(address(rescuer).balance, balance - withdrawal);
        assertEq(address(receiver).balance, withdrawal);
    }

    function test_withdraw_FailsIf_ETHTransferFails(
        uint balance,
        uint withdrawal
    ) public {
        vm.assume(balance >= withdrawal);

        // Let rescuer have ETH balance.
        vm.deal(address(rescuer), balance);

        // Deploy non ETH receiver.
        NotETHReceiver receiver = new NotETHReceiver();

        vm.expectRevert();
        rescuer.withdraw(payable(address(receiver)), withdrawal);
    }

    function test_withdraw_isAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        rescuer.withdraw(payable(address(this)), 0);
    }

    // -- Helpers --

    function _constructOpPokeSig(LibFeed.Feed memory feed, uint32 pokeDataAge)
        internal
        view
        returns (IScribe.ECDSAData memory)
    {
        // Construct pokeData with zero val and given age.
        IScribe.PokeData memory pokeData = IScribe.PokeData(0, pokeDataAge);

        // Construct invalid Schnorr signature.
        IScribe.SchnorrData memory schnorrData =
            IScribe.SchnorrData(bytes32(0), address(0), hex"");

        // Construct opPokeMessage.
        bytes32 opPokeMessage =
            opScribe.constructOpPokeMessage(pokeData, schnorrData);

        // Let feed sign opPokeMessage.
        return feed.signECDSA(opPokeMessage);
    }
}

contract NotETHReceiver {}

contract ETHReceiver {
    receive() external payable {}
}
