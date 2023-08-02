// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

import {Chaincheck} from "@script/chronicle-std/Chaincheck.sol";
import {IAuthChaincheck} from "@script/chronicle-std/IAuthChaincheck.sol";
import {ITollChaincheck} from "@script/chronicle-std/ITollChaincheck.sol";

import {IScribe} from "src/IScribe.sol";

/**
 * @notice IScribe's `chaincheck` Integration Test
 *
 * @dev Config Definition:
 *      ```json
 *      {
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
 *          },
 *          "IAuth": {
 *              "legacy": bool,
 *              "authed": [
 *                  "<Ethereum address>",
 *                  ...
 *              ]
 *          },
 *          "IToll": {
 *              "legacy": bool,
 *              "authed": [
 *                  "<Ethereum address>",
 *                  ...
 *              ]
 *          }
 *      }
 *      ```
 */
contract IScribeChaincheck is Chaincheck {
    using stdJson for string;

    Vm internal constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    IScribe self;
    string config;

    string[] logs;

    function setUp(address self_, string memory config_)
        public
        virtual
        override(Chaincheck)
        returns (Chaincheck)
    {
        self = IScribe(self_);
        config = config_;

        return Chaincheck(address(this));
    }

    function run()
        public
        virtual
        override(Chaincheck)
        returns (bool, string[] memory)
    {
        check_wat();
        check_bar();
        check_decimals();
        check_feeds();

        // Check dependencies.
        check_IAuth();
        check_IToll();

        // Fail run if non-zero number of logs.
        return (logs.length == 0, logs);
    }

    function check_wat() internal {
        bytes32 want = toBytes32(config.readString("IScribe.wat"));
        bytes32 got = self.wat();

        if (want != got) {
            logs.push(
                string.concat(
                    StdStyle.red("Wat mismatch:"),
                    " expected=",
                    vm.toString(want),
                    ", actual=",
                    vm.toString(got)
                )
            );
        }
    }

    function check_bar() internal {
        uint8 want = uint8(config.readUint(".IScribe.bar"));
        uint8 got = self.bar();

        if (want != got) {
            logs.push(
                string.concat(
                    StdStyle.red("Bar mismatch:"),
                    " expected=",
                    vm.toString(want),
                    ", actual=",
                    vm.toString(got)
                )
            );
        }
    }

    function check_decimals() internal {
        uint8 want = uint8(config.readUint(".IScribe.decimals"));
        uint8 got = self.decimals();

        if (want != got) {
            logs.push(
                string.concat(
                    StdStyle.red("Decimals mismatch:"),
                    " expected=",
                    vm.toString(want),
                    ", actual=",
                    vm.toString(got)
                )
            );
        }
    }

    function check_feeds() internal {
        address[] memory wantFeeds = config.readAddressArray("IScribe.feeds");
        uint[] memory wantFeedIndexes =
            config.readUintArray("IScribe.feedIndexes");

        // Return early if config is erroneous.
        if (wantFeeds.length != wantFeedIndexes.length) {
            logs.push(
                string.concat(
                    StdStyle.red(
                        "Config error: feeds.length != feedIndexes.length"
                    )
                )
            );
            return;
        }

        // Check that each expected feed is lifted and has corresponding feed
        // index.
        address wantFeed;
        uint wantFeedIndex;
        for (uint i; i < wantFeeds.length; i++) {
            wantFeed = wantFeeds[i];
            wantFeedIndex = wantFeedIndexes[i];

            bool isFeed;
            uint gotFeedIndex;
            (isFeed, gotFeedIndex) = self.feeds(wantFeed);

            if (!isFeed) {
                logs.push(
                    string.concat(
                        StdStyle.red("Expected feed not lifted:"),
                        " feed=",
                        vm.toString(wantFeed)
                    )
                );
                continue;
            }

            if (wantFeedIndex != gotFeedIndex) {
                logs.push(
                    string.concat(
                        StdStyle.red("Expected feed index does not match:"),
                        " feed=",
                        vm.toString(wantFeed),
                        ", expectedIndex=",
                        vm.toString(wantFeedIndex),
                        ", actualIndex=",
                        vm.toString(gotFeedIndex)
                    )
                );
                continue;
            }
        }

        // Check that only expected feeds are lifted.
        address[] memory gotFeeds;
        (gotFeeds, /*feedIndexes*/ ) = self.feeds();
        for (uint i; i < gotFeeds.length; i++) {
            for (uint j; j < wantFeeds.length; j++) {
                if (gotFeeds[i] == wantFeeds[j]) {
                    // Feed is expected, break inner loop.
                    break;
                }

                if (j == wantFeeds.length - 1) {
                    // Feed not found.
                    logs.push(
                        string.concat(
                            StdStyle.red("Unknown feed lifted:"),
                            " feed=",
                            vm.toString(gotFeeds[i])
                        )
                    );
                }
            }
        }
    }

    /// @dev Checks the IAuth module dependency.
    function check_IAuth() internal {
        // Run IAuth chaincheck.
        string[] memory authLogs;
        (, authLogs) = new IAuthChaincheck()
                            .setUp(address(self), config)
                            .run();

        // Add logs to own logs.
        for (uint i; i < authLogs.length; i++) {
            logs.push(authLogs[i]);
        }
    }

    /// @dev Checks the IToll module dependency.
    function check_IToll() internal {
        // Run IToll chaincheck.
        string[] memory authLogs;
        (, authLogs) = new ITollChaincheck()
                            .setUp(address(self), config)
                            .run();

        // Add logs to own logs.
        for (uint i; i < authLogs.length; i++) {
            logs.push(authLogs[i]);
        }
    }

    // -- Internal Helpers --

    function toBytes32(string memory str) internal pure returns (bytes32) {
        if (bytes(str).length == 0) {
            return 0;
        }

        bytes32 result;
        assembly ("memory-safe") {
            result := mload(add(str, 0x20))
        }
        return result;
    }
}
