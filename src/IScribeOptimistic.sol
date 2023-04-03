pragma solidity ^0.8.16;

import {IScribe} from "./IScribe.sol";

interface IScribeOptimistic is IScribe {
    struct ECDSASignatureData {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error InChallengePeriod();

    error ArgumentsDoNotMatchOpCommitment(
        bytes32 argumentsHash, bytes32 opCommitment
    );
    error NoOpPokeToChallenge();

    event OpPoked(
        address indexed caller,
        address indexed opFeed,
        uint val,
        uint32 age,
        bytes32 opCommitment
    );
    event OpPokeDataDropped(address indexed caller, uint128 val, uint32 age);

    event OpPokeSuccessfullyChallenged(
        address indexed caller,
        bytes32 opCommitment,
        uint bounty,
        bytes schnorrSignatureDataError
    );
    event OpPokeUnsuccessfullyChallenged(
        address indexed caller, bytes32 opCommitment
    );

    function opPoke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData,
        ECDSASignatureData calldata ecdsaSignatureData
    ) external payable;

    function opChallenge(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData
    ) external payable;

    function opFeed() external view returns (address);
    function opCommitment() external view returns (bytes32);
}
