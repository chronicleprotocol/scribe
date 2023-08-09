// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

import {Chaincheck} from "@script/chronicle-std/Chaincheck.sol";
import {IAuthChaincheck} from "@script/chronicle-std/IAuthChaincheck.sol";
import {ITollChaincheck} from "@script/chronicle-std/ITollChaincheck.sol";

import {IScribe} from "src/IScribe.sol";
import {IScribeOptimistic} from "src/IScribeOptimistic.sol";

import {IScribeChaincheck} from "./IScribeChaincheck.sol";

/**
 * @notice IScribeOptimistic's `chaincheck` Integration Test
 *
 * @dev Config Definition:
 *
 *      ```json
 *      {
 *          "IScribeOptimistic": {
 *              "opChallengePeriod": <timestamp>,
 *              "challengeReward": <ETH amount in wei>,
 *              "maxChallengeReward": <ETH amount in wei>
 *          },
 *          "IScribe": {
 *              "wat": "ETH/USD",
 *              "bar": 13,
 *              "decimals": 18,
 *              "feeds": [
 *                  "<Ethereum address>",
 *                  ...
 *              ],
 *              "feedIndexes": [
 *                  0,
 *                  ...
 *              ],
 *              "feedPublicKeys": {
 *                  "xCoordinates": [
 *                      <uint>,
 *                      ...
 *                  ],
 *                  "yCoordinates": [
 *                      <uint>,
 *                      ...
 *                  ]
 *              }
 *          },
 *          "IAuth": {
 *              "legacy": <bool>,
 *              "authed": [
 *                  "<Ethereum address>",
 *                  ...
 *              ]
 *          },
 *          "IToll": {
 *              "legacy": <bool>,
 *              "authed": [
 *                  "<Ethereum address>",
 *                  ...
 *              ]
 *          }
 *      }
 *      ```
 */
contract IScribeOptimisticChaincheck is IScribeChaincheck {
    using stdJson for string;

    function setUp(address self_, string memory config_)
        public
        override(IScribeChaincheck)
        returns (Chaincheck)
    {
        return super.setUp(self_, config_);
    }

    function run()
        public
        override(IScribeChaincheck)
        returns (bool, string[] memory)
    {
        // Configurations:
        check_opChallengePeriod();
        check_challengeReward();
        check_maxChallengeReward();

        // Run IScribe's chaincheck.
        super.run();

        // Fail run if non-zero number of logs.
        return (logs.length == 0, logs);
    }

    function check_opChallengePeriod() internal {
        uint want = config.readUint(".IScribeOptimistic.opChallengePeriod");
        uint got = IScribeOptimistic(address(self)).opChallengePeriod();

        if (want != got) {
            logs.push(
                string.concat(
                    StdStyle.red("opChallenge Period mismatch:"),
                    " expected=",
                    vm.toString(want),
                    ", actual=",
                    vm.toString(got)
                )
            );
        }
    }

    function check_challengeReward() internal {
        uint want = config.readUint(".IScribeOptimistic.challengeReward");
        uint got = IScribeOptimistic(address(self)).challengeReward();

        if (want != got) {
            logs.push(
                string.concat(
                    StdStyle.red("Challenge Reward mismatch:"),
                    " expected=",
                    vm.toString(want),
                    ", actual=",
                    vm.toString(got)
                )
            );
        }
    }

    function check_maxChallengeReward() internal {
        uint want = config.readUint(".IScribeOptimistic.maxChallengeReward");
        uint got = IScribeOptimistic(address(self)).maxChallengeReward();

        if (want != got) {
            logs.push(
                string.concat(
                    StdStyle.red("Max Challenge Reward mismatch:"),
                    " expected=",
                    vm.toString(want),
                    ", actual=",
                    vm.toString(got)
                )
            );
        }
    }
}
