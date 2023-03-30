pragma solidity ^0.8.16;

import {IScribeAuth} from "./IScribeAuth.sol";

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

interface IScribeOptimisticAuth is IScribeAuth {
    event OpChallengePeriodUpdated(
        address indexed caller,
        uint16 oldOpChallengePeriod,
        uint16 newOpChallengePeriod
    );

    function opChallengePeriod() external view returns (uint16);
    function setOpChallengePeriod(uint16 opChallengePeriod) external;
}
