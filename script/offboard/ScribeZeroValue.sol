// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title ScribeZeroValue
 *
 * @notice Static scribe oracle returning zero or reverting on read functions
 *
 * @dev Deployment:
 *      ```bash
 *      $ forge create script/offboarder/ScribeZeroValue.sol:ScribeZeroValue \
 *          --keystore $KEYSTORE \
 *          --password $KEYSTORE_PASSWORD \
 *          --rpc-url $RPC_URL \
 *          --verifier-url $ETHERSCAN_API_URL \
 *          --etherscan-api-key $ETHERSCAN_API_KEY
 *      ```
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract ScribeZeroValue {
    function read() external pure returns (uint) {
        revert();
    }

    function tryRead() external pure returns (bool, uint) {
        return (false, 0);
    }

    function readWithAge() external pure returns (uint, uint) {
        revert();
    }

    function tryReadWithAge() external pure returns (bool, uint, uint) {
        return (false, 0, 0);
    }

    // - MakerDAO Compatibility

    function peek() external pure returns (uint, bool) {
        return (0, false);
    }

    function peep() external pure returns (uint, bool) {
        return (0, false);
    }

    // - Chainlink Compatibility

    function latestRoundData()
        external
        pure
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 1;
        answer = 0;
        startedAt = 0;
        updatedAt = 0;
        answeredInRound = roundId;
    }

    function latestAnswer() external pure returns (int) {
        int answer = 0;
        return answer;
    }
}
