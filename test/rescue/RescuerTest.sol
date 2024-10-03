// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

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

    event Recovered(
        address indexed caller, address indexed opScribe, uint amount
    );
    event Withdrawed(
        address indexed caller, address indexed receiver, uint amount
    );

    IScribeOptimistic private scribe;
    Rescuer private rescuer;

    function setUp() public {
        scribe = new ScribeOptimistic(address(this), bytes32("TEST/TEST"));
        IScribeOptimistic(scribe).setMaxChallengeReward(type(uint).max);
        rescuer = new Rescuer(address(this));
    }

    function test_suck() public {
        // Auth the recover contract on scribe
        IAuth(address(scribe)).rely(address(rescuer));
        // Send some Eth to the scribe contract
        vm.deal(address(scribe), 1 ether);
        // Create a new feed
        LibFeed.Feed memory feed = LibFeed.newFeed(1);
        // Create registration sig
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            feed.signECDSA(scribe.feedRegistrationMessage());
        // Construct opPokeSignature, (with invalid schnorr sig)
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig = _construct_opPokeSignature(feed, pokeDataAge);
        // Rescue ETH via rescuer contract.
        vm.expectEmit();
            emit Recovered(address(this), address(scribe), 1 ether);
        rescuer.suck(
            address(scribe), feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
        // Withdraw the eth
        uint current_balance = address(this).balance;
        uint withdraw_amount = address(rescuer).balance;
        address recipient = address(0x1234567890123456789012345678901234567890);
        vm.expectEmit();
            emit Withdrawed(address(this), recipient, withdraw_amount);
        rescuer.withdraw(payable(recipient), withdraw_amount);
        assertEq(recipient.balance, withdraw_amount);

    }

    function test_suckMultiple() public {
        address[] memory scribes = new address[](10);
        for (uint i = 0; i < 10; i++) {
            scribes[i] = address(new ScribeOptimistic(address(this), bytes32("TEST/TEST")));
            IScribeOptimistic(scribes[i]).setMaxChallengeReward(type(uint).max);
            // Auth the recover contract on scribe
            IAuth(address(scribes[i])).rely(address(rescuer));
            vm.deal(address(scribes[i]), 1 ether);
        }
        // Create a new feed
        LibFeed.Feed memory feed = LibFeed.newFeed(1);
        // Create registration sig
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            feed.signECDSA(scribe.feedRegistrationMessage());
        // Construct opPokeSignature, (with invalid schnorr sig)
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig = _construct_opPokeSignature(feed, pokeDataAge);
        // Rescue ETH via rescuer contract.
        for (uint i = 0; i < 10; i++) {
             vm.expectEmit();
            emit Recovered(address(this), address(scribes[i]), 1 ether);
        }
        rescuer.suck(
            scribes, feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
        // Withdraw the eth
        uint current_balance = address(this).balance;
        uint withdraw_amount = address(rescuer).balance;
        address recipient = address(0x1234567890123456789012345678901234567890);
        vm.expectEmit();
            emit Withdrawed(address(this), recipient, withdraw_amount);
        rescuer.withdraw(payable(recipient), withdraw_amount);
        assertEq(recipient.balance, withdraw_amount);

    }

    function test_suck_FailsIf_rescuerNotAuthed() public {
        // Send some Eth to the scribe contract
        vm.deal(address(scribe), 1 ether);
        // Create a new feed
        LibFeed.Feed memory feed = LibFeed.newFeed(1);
        // Create registration sig
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            feed.signECDSA(scribe.feedRegistrationMessage());
        // Construct opPokeSignature, (with invalid schnorr sig)
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig = _construct_opPokeSignature(feed, pokeDataAge);
        // Rescue ETH via rescuer contract.
        vm.expectRevert();
        rescuer.suck(
            address(scribe), feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
    }

    function test_suck_FailsIf_feedsLengthNotZero() public {
        // Create a new feed to lift on scribe
        LibFeed.Feed memory existing_feed = LibFeed.newFeed(1);
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            existing_feed.signECDSA(scribe.feedRegistrationMessage());
        // Lift validator.
        scribe.lift(existing_feed.pubKey, registrationSig);
        // Auth the recover contract on scribe
        IAuth(address(scribe)).rely(address(rescuer));
        // Send some Eth to the scribe contract
        vm.deal(address(scribe), 1 ether);
        // Create a new feed
        LibFeed.Feed memory feed = LibFeed.newFeed(2);
        // Create registration sig
        registrationSig =
            feed.signECDSA(scribe.feedRegistrationMessage());
        // Construct opPokeSignature, (with invalid schnorr sig)
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig = _construct_opPokeSignature(feed, pokeDataAge);
        // Rescue ETH via rescuer contract.
        vm.expectRevert();
        rescuer.suck(
            address(scribe), feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
    }

    function test_suck_FailsIf_challengeFails() public {
        // Auth the recover contract on scribe
        IAuth(address(scribe)).rely(address(rescuer));
        // Send some Eth to the scribe contract
        vm.deal(address(scribe), 1 ether);
        // Create a new feed
        LibFeed.Feed memory feed = LibFeed.newFeed(1);
        // Create registration sig
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            feed.signECDSA(scribe.feedRegistrationMessage());
        // Construct opPokeSignature using a different feed private key, (with invalid schnorr sig)
        uint32 pokeDataAge = uint32(block.timestamp);
        LibFeed.Feed memory unlifted_feed = LibFeed.newFeed(2);
        IScribe.ECDSAData memory opPokeSig = _construct_opPokeSignature(unlifted_feed, pokeDataAge);
        // Rescue ETH via rescuer contract.
        vm.expectRevert();
        rescuer.suck(
            address(scribe), feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
    }


    function testFuzz_withdraw(uint amount) public {
        amount = _bound(amount, 0, 1000 ether);
        // Send some Eth to the rescuer contract
        vm.deal(address(rescuer), amount);
        uint withdraw_amount = address(rescuer).balance;
        address recipient = address(0x1234567890123456789012345678901234567890);
        vm.expectEmit();
            emit Withdrawed(address(this), recipient, withdraw_amount);
        rescuer.withdraw(payable(recipient), withdraw_amount);
        assertEq(recipient.balance, withdraw_amount);
        assertEq(withdraw_amount, amount);
    }

    // Auth tests

    function test_suck_isAuthed() public {
        // Deauth this on the rescuer contract
        IAuth(address(rescuer)).deny(address(this));
        // Send some Eth to the scribe contract
        vm.deal(address(scribe), 1 ether);
        // Create a new feed
        LibFeed.Feed memory feed = LibFeed.newFeed(1);
        // Create registration sig
        IScribe.ECDSAData memory registrationSig;
        registrationSig =
            feed.signECDSA(scribe.feedRegistrationMessage());
        // Construct opPokeSignature, (with invalid schnorr sig)
        uint32 pokeDataAge = uint32(block.timestamp);
        IScribe.ECDSAData memory opPokeSig = _construct_opPokeSignature(feed, pokeDataAge);
        // Rescue ETH via rescuer contract.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(this)
            )
        );
        // TODO correct revert
        rescuer.suck(
            address(scribe), feed.pubKey, registrationSig, pokeDataAge, opPokeSig
        );
    }

    function test_withdraw_isAuthed() public {
        // Deauth this on the rescuer contract
        IAuth(address(rescuer)).deny(address(this));
        // Send some Eth to the rescuer contract
        vm.deal(address(rescuer), 1 ether);
        uint withdraw_amount = address(rescuer).balance;
        address recipient = address(0x1234567890123456789012345678901234567890);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(this)
            )
        );
        rescuer.withdraw(payable(recipient), withdraw_amount);
    }


    function _construct_opPokeSignature(LibFeed.Feed memory feed, uint32 pokeDataAge) private returns (IScribe.ECDSAData memory) {
        IScribe.PokeData memory pokeData = IScribe.PokeData(0, pokeDataAge);
        IScribe.SchnorrData memory schnorrData =
            IScribe.SchnorrData(bytes32(0), address(0), hex"");
        // Construct opPokeMessage.
        bytes32 opPokeMessage = scribe.constructOpPokeMessage(
            pokeData, schnorrData
        );
        // Let feed sign opPokeMessage.
        IScribe.ECDSAData memory opPokeSig = feed.signECDSA(opPokeMessage);
        return opPokeSig;
    }

}
