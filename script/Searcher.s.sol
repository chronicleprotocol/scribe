pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

/**
 * @title MEV Searcher Script
 *
 * @dev
 */
contract Searcher is Script {
    // @todo Wallet from pk via env variables.
    address wallet = address(0xdead);

    IScribeOptimistic opScribe = IScribeOptimistic(address(0xcafe));

    function run(
        bytes32 pokeMessage,
        IScribeOptimistic.SchnorrSignatureData memory schnorrData,
        uint opPokeTimestamp
    ) public {
        // Check whether last opPoke already finalized.
        uint opChallengePeriod = opScribe.opChallengePeriod();
        if (opPokeTimestamp + opChallengePeriod <= block.timestamp) {
            console2.log("Searcher::run: opPoke finalized");
            return;
        }

        // Check whether last opPoke's schnorr data ok.
        (bool ok, bytes memory err) =
            opScribe.verifySchnorrSignature(pokeMessage, schnorrData);
        if (ok) {
            console2.log("Searcher::run: opPoke schnorr data ok");
            return;
        }

        uint reward = address(opScribe).balance;
        uint balanceBefore = wallet.balance;

        console2.log("!!! Searcher::run: opPoke challengeable !!!");
        console2.log(
            "==> Searcher::run:  verification error: ", vm.toString(err)
        );
        console2.log(
            "==> Searcher::run: expected reward: ", vm.toString(reward)
        );
        console2.log(
            "==> Searcher::run: current balance: ", vm.toString(balanceBefore)
        );

        // Challenge last opPoke.
        ok = opScribe.opChallenge(schnorrData);
        if (!ok) {
            // !!! THIS MUST NOT HAPPEN !!!
            console2.log("==> [ERROR] Searcher::run: challenging failed");
            assert(false);
        }

        uint balanceAfter = wallet.balance;
        console2.log("==> Searcher::run: challenging succeeded");
        console2.log(
            "==> Searcher::run: balance after: ", vm.toString(balanceAfter)
        );
    }
}
