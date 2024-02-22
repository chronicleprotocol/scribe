// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

/**
 * @dev Interest rate oracle interface from [Spark](https://spark.fi/).
 *
 *      Copied from https://github.com/marsfoundation/sparklend-advanced/blob/277ea9d9ad7faf330b88198c9c6de979a2fad561/src/interfaces/IRateSource.sol.
 */
interface IRateSource {
    /// @notice Returns the oracle's current APR value.
    /// @return The oracle's current APR value.
    function getAPR() external view returns (uint);
}
