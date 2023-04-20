pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

/**
 * @title Governance Script
 */
contract Governance is Script {
    IScribe scribe = IScribe(address(0xcafe));
    IScribeOptimistic opScribe = IScribeOptimistic(address(0xcafe));

    function setBar(uint8 bar) public {}

    function rely() public {}

    function deny() public {}

    function lift() public {}

    function drop() public {}

    // IScribeOptimistic:

    function setOpChallengePeriod() public {}
}
