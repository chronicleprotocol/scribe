pragma solidity ^0.8.16;

import {stdJson} from "forge-std/StdJson.sol";
import {StdStyle} from "forge-std/StdStyle.sol";

import {Chaincheck} from "@script/chronicle-std/Chaincheck.sol";
import {IAuthChaincheck} from "@script/chronicle-std/IAuthChaincheck.sol";

import {IScribe} from "src/IScribe.sol";

/**
 * @notice IScribe's `chaincheck` Integration Test
 *
 * @dev Config Definition: TODO Note that only part of the whole config. Just the part checked.
 *
 *      ```json
 *      {
 *          "IScribe": {
 *              "...": [
 *                  ...
 *              ],
 *          },
 *      }
 *      ```
 */
contract IScribeChaincheck is Chaincheck {
    using stdJson for string;

    IScribe self;
    string config;

    string[] _logs;

    function setUp(address self_, string memory config_)
        external
        override(Chaincheck)
        returns (Chaincheck)
    {
        self = IScribe(self_);
        config = config_;

        return Chaincheck(address(this));
    }

    function run()
        external
        override(Chaincheck)
        returns (bool, string[] memory)
    {
        check_IAuth();

        // Fail run if non-zero number of logs.
        return (_logs.length == 0, _logs);
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
            _logs.push(authLogs[i]);
        }
    }
}
