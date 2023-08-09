pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {Chaincheck} from "@script/chronicle-std/Chaincheck.sol";
import {IAuthChaincheck} from "@script/chronicle-std/IAuthChaincheck.sol";
import {ITollChaincheck} from "@script/chronicle-std/ITollChaincheck.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";

import {
    LibPublicKeyVerifier,
    LibSignerSet
} from "../libs/LibPublicKeyVerifier.sol";

/**
 * @notice IScribe's `chaincheck` Integration Test
 *
 * @dev Note that this `chaincheck` has a runtime of and memory consumption of
 *      ω(2^#feeds). If the script fails with "EVMError: MemoryLimitOOG",
 *      increase the memory limit via the `--memory-limit` flag.
 *
 * @dev Config Definition:
 *
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
contract IScribeChaincheck is Chaincheck {
    using stdJson for string;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibPublicKeyVerifier for LibPublicKeyVerifier.PublicKeyVerifier;

    Vm internal constant vm =
        Vm(address(uint160(uint(keccak256("hevm cheat code")))));

    IScribe self;
    string config;

    string[] logs;

    // Necessary for check_invariant_PubKeysHaveNoLinearRelationship().
    LibPublicKeyVerifier.PublicKeyVerifier pubKeyVerifier;

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
        // Config:
        check_feeds_ConfigSanity();

        // Constants:
        check_wat();
        check_decimals();

        // Configurations:
        check_bar();
        check_feeds_AllExpectedFeedsAreLifted();
        check_feeds_OnlyExpectedFeedsAreLifted();
        check_feeds_AllExpectedFeedIndexesLinkToCorrectFeed();
        check_feeds_AllPublicKeysAreLifted();
        check_feeds_PublicKeysCorrectlyOrdered();

        // Invariants:
        check_invariant_ZeroPublicKeyIsNotLifted();
        // Note that check is disabled due to heavy memory usage making it
        // currently unusable in ci.
        // @todo: Try to fix. However, problem is NP hard so most likely need
        //        more resources in ci or utilize some caching strategy.
        //check_invariant_PublicKeysHaveNoLinearRelationship();
        check_invariant_BarIsNotZero();
        check_invariant_ReadFunctionsReturnSameValue();

        // Dependencies:
        check_IAuth();
        check_IToll();

        // Fail run if non-zero number of logs.
        return (logs.length == 0, logs);
    }

    // -- Config --

    function check_feeds_ConfigSanity() internal {
        address[] memory feeds = config.readAddressArray(".IScribe.feeds");
        uint[] memory feedIndexes = config.readUintArray(".IScribe.feedIndexes");
        uint[] memory feedPublicKeysXCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.xCoordinates");
        uint[] memory feedPublicKeysYCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.yCoordinates");

        uint wantLen = feeds.length;

        if (feedIndexes.length != wantLen) {
            logs.push(
                string.concat(
                    StdStyle.red(
                        "Config error: IScribe.feeds.length != IScribe.feedIndexes.length"
                    )
                )
            );
        }

        if (feedPublicKeysXCoordinates.length != wantLen) {
            logs.push(
                string.concat(
                    StdStyle.red(
                        "Config error: IScribe.feeds.length != IScribe.feedPublicKeys.xCoordinates.length"
                    )
                )
            );
        }

        if (feedPublicKeysYCoordinates.length != wantLen) {
            logs.push(
                string.concat(
                    StdStyle.red(
                        "Config error: IScribe.feeds.length != IScribe.feedPublicKey.yCoordinates.length"
                    )
                )
            );
        }
    }

    // -- Constants --

    function check_wat() internal {
        bytes32 want = toBytes32(config.readString(".IScribe.wat"));
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

    // -- Configurations --

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

    function check_feeds_AllExpectedFeedsAreLifted() internal {
        address[] memory wantFeeds = config.readAddressArray(".IScribe.feeds");

        // Check that each expected feeds are lifted.
        address wantFeed;
        for (uint i; i < wantFeeds.length; i++) {
            wantFeed = wantFeeds[i];

            bool isFeed;
            (isFeed, /*feedIndex*/ ) = self.feeds(wantFeed);

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
        }
    }

    function check_feeds_OnlyExpectedFeedsAreLifted() internal {
        address[] memory wantFeeds = config.readAddressArray(".IScribe.feeds");

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

    function check_feeds_AllExpectedFeedIndexesLinkToCorrectFeed() internal {
        address[] memory wantFeeds = config.readAddressArray(".IScribe.feeds");
        uint[] memory wantFeedIndexes =
            config.readUintArray(".IScribe.feedIndexes");

        // Check that each feed index links to correct feed.
        address wantFeed;
        uint wantFeedIndex;
        for (uint i; i < wantFeeds.length; i++) {
            wantFeed = wantFeeds[i];
            wantFeedIndex = wantFeedIndexes[i];

            bool isFeed;
            uint gotFeedIndex;
            (isFeed, gotFeedIndex) = self.feeds(wantFeed);

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
    }

    function check_feeds_AllPublicKeysAreLifted() internal {
        uint[] memory feedPublicKeysXCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.xCoordinates");
        uint[] memory feedPublicKeysYCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.yCoordinates");

        // Make LibSecp256k1.Point types from coordinates.
        LibSecp256k1.Point[] memory pubKeys;
        pubKeys = new LibSecp256k1.Point[](feedPublicKeysXCoordinates.length);
        for (uint i; i < pubKeys.length; i++) {
            pubKeys[i] = LibSecp256k1.Point({
                x: feedPublicKeysXCoordinates[i],
                y: feedPublicKeysYCoordinates[i]
            });
        }

        // Derive addresses of public keys.
        address[] memory addrs = new address[](pubKeys.length);
        for (uint i; i < addrs.length; i++) {
            addrs[i] = pubKeys[i].toAddress();
        }

        // Check that each address derived from public key is lifted.
        for (uint i; i < addrs.length; i++) {
            bool isFeed;
            (isFeed, /*feedIndex*/ ) = self.feeds(addrs[i]);

            if (!isFeed) {
                logs.push(
                    string.concat(
                        StdStyle.red("Expected feed public key not lifted:"),
                        " feed=",
                        vm.toString(addrs[i]),
                        ", public key x coordinate=",
                        vm.toString(pubKeys[i].x),
                        ", public key y coordinate=",
                        vm.toString(pubKeys[i].y)
                    )
                );
            }
        }
    }

    function check_feeds_PublicKeysCorrectlyOrdered() internal {
        uint[] memory feedPublicKeysXCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.xCoordinates");
        uint[] memory feedPublicKeysYCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.yCoordinates");

        // Make LibSecp256k1.Point types from coordinates.
        LibSecp256k1.Point[] memory pubKeys;
        pubKeys = new LibSecp256k1.Point[](feedPublicKeysXCoordinates.length);
        for (uint i; i < pubKeys.length; i++) {
            pubKeys[i] = LibSecp256k1.Point({
                x: feedPublicKeysXCoordinates[i],
                y: feedPublicKeysYCoordinates[i]
            });
        }

        // Derive addresses of public keys.
        address[] memory addrs = new address[](pubKeys.length);
        for (uint i; i < addrs.length; i++) {
            addrs[i] = pubKeys[i].toAddress();
        }

        // Load feed addresses from config.
        address[] memory feeds = config.readAddressArray(".IScribe.feeds");

        // Check that order of lists match.
        for (uint i; i < addrs.length; i++) {
            if (addrs[i] != feeds[i]) {
                logs.push(StdStyle.red("Public keys not correctly ordered"));
            }
        }
    }

    // -- Invariants --

    function check_invariant_ZeroPublicKeyIsNotLifted() internal {
        bool isFeed;
        (isFeed, /*feedIndex*/ ) =
            self.feeds(LibSecp256k1.ZERO_POINT().toAddress());

        if (isFeed) {
            logs.push(
                StdStyle.red("[INVARIANT BROKEN] Zero public key is lifted")
            );
        }
    }

    function check_invariant_PublicKeysHaveNoLinearRelationship() internal {
        uint[] memory feedPublicKeysXCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.xCoordinates");
        uint[] memory feedPublicKeysYCoordinates =
            config.readUintArray(".IScribe.feedPublicKeys.yCoordinates");

        // Make LibSecp256k1.Point types from coordinates.
        LibSecp256k1.Point[] memory pubKeys;
        pubKeys = new LibSecp256k1.Point[](feedPublicKeysXCoordinates.length);
        for (uint i; i < pubKeys.length; i++) {
            pubKeys[i] = LibSecp256k1.Point({
                x: feedPublicKeysXCoordinates[i],
                y: feedPublicKeysYCoordinates[i]
            });
        }

        bool ok;
        (ok, /*set1*/, /*set2*/ ) = pubKeyVerifier.verifyPublicKeys(pubKeys);
        if (!ok) {
            logs.push(
                StdStyle.red(
                    "[INVARIANT BROKEN] Public keys have linear relationship"
                )
            );
        }
    }

    function check_invariant_BarIsNotZero() internal {
        if (self.bar() == 0) {
            logs.push(StdStyle.red("[INVARIANT BROKEN] Bar is zero"));
        }
    }

    function check_invariant_ReadFunctionsReturnSameValue() internal {
        // Note to make sure address(this) is tolled.
        address addrThis = address(this);
        vm.prank(IAuth(address(self)).authed()[0]);
        IToll(address(self)).kiss(addrThis);

        // Treat tryReadWithAge as source of truth.
        bool isValidWant;
        uint valWant;
        uint ageWant;
        (isValidWant, valWant, ageWant) = self.tryReadWithAge();

        string memory log = StdStyle.red(
            "[INVARIANT BROKEN] Different answers in read functions"
        );

        bool isValidGot;
        uint valGot;

        // - IChronicle Functions
        if (isValidWant) {
            if (self.read() != valWant) {
                logs.push(log);
            }

            valGot;
            uint ageGot;
            (valGot, ageGot) = self.readWithAge();
            if (valGot != valWant || ageGot != ageWant) {
                logs.push(log);
            }
        } else {
            try self.read() returns (uint) {
                logs.push(log);
            } catch {}

            try self.readWithAge() returns (uint, uint) {
                logs.push(log);
            } catch {}
        }

        (isValidGot, valGot) = self.tryRead();
        if (isValidGot != isValidWant || valGot != valWant) {
            logs.push(log);
        }

        // - Chainlink Compatibility Functions
        int answer;
        uint updatedAt;
        ( /*roundId*/ , answer, /*startedAt*/, updatedAt, /*answeredInRound*/ )
        = self.latestRoundData();
        if (uint(answer) != valWant || updatedAt != ageWant) {
            logs.push(log);
        }

        // - MakerDAO Compatibility Functions
        (valGot, isValidGot) = self.peek();
        if (valGot != valWant || isValidGot != isValidWant) {
            logs.push(log);
        }
    }

    // -- Dependency Checks --

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

    // -- Helpers --

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
