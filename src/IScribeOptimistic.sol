pragma solidity ^0.8.16;

import {IScribe} from "./IScribe.sol";

interface IScribeOptimistic is IScribe {
    error InChallengePeriod();

    error ArgumentsDoNotMatchOpCommitment(
        bytes32 argumentsHash, bytes32 opCommitment
    );
    error NoOpPokeToChallenge();

    event OpPokeDataDropped(address indexed caller, uint128 val, uint32 age);

    function opPoke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData,
        ECDSASignatureData calldata ecdsaSignatureData
    ) external;

    function opChallenge(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData
    ) external;

    function opFeed() external view returns (address);
    function opCommitment() external view returns (bytes32);
}
