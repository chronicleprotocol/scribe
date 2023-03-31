pragma solidity ^0.8.16;

interface IScribe {
    struct PokeData {
        uint128 val;
        uint32 age;
    }

    struct SchnorrSignatureData {
        address[] signers;
        bytes32 signature;
        address commitment;
    }

    error StaleMessage(uint32 givenAge, uint32 currentAge);
    error BarNotReached(uint8 numberSigners, uint8 bar);
    error SignerNotFeed(address signer);
    error SignersNotOrdered();
    error SchnorrSignatureInvalid();

    function poke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData
    ) external;

    function read() external view returns (uint);
    function peek() external view returns (uint, bool);

    function wat() external view returns (bytes32);
}
