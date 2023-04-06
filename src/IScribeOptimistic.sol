pragma solidity ^0.8.16;

import {IScribe} from "./IScribe.sol";

interface IScribeOptimistic is IScribe {
    /// @notice Thrown if attempted to opPoke while a previous opPoke is still
    ///         in challenge period.
    error InChallengePeriod();

    // @todo Rename error.
    /// @notice Thrown if opChallenge arguments do not match arguments of
    ///         corresponding opPoke, i.e. the opPoke arguments the opFeed
    ///         committed themselves to.
    error ArgumentsDoNotMatchOpCommitment(
        bytes32 argumentsHash, bytes32 opCommitment
    );

    /// @notice Thrown if opChallenge called while no opPoke exists thats
    ///         challengeable.
    error NoOpPokeToChallenge();

    /// @notice Emitted when oracles was successfully opPoked.
    /// @param caller The caller's address.
    /// @param opFeed The feed that signed the opPoke.
    /// @param val The value opPoked.
    /// @param age The age of the value opPoked.
    /// @param opCommitment The hash of the opPoke arguments, i.e. the arguments
    ///                     opFeed committed themselves to.
    event OpPoked(
        address indexed caller,
        address indexed opFeed,
        uint val,
        uint32 age,
        bytes32 opCommitment
    );

    /// @notice Emitted when an opPoke dropped.
    /// @dev opPoke's are dropped if security parameters are updated that could
    ///      lead to an initially valid opPoke becoming invalid or an opPoke was
    ///      was successfully challenged.
    /// @param caller The caller's address.
    /// @param val The opPoke's value dropped.
    /// @param age The opPoke's value's age dropped.
    event OpPokeDataDropped(address indexed caller, uint128 val, uint32 age);

    /// @notice Emitted when length of opChallengePeriod updated.
    /// @param caller The caller's address.
    /// @param oldOpChallengePeriod The old opChallengePeriod's length.
    /// @param newOpChallengePeriod The new opChallengePeriod's length.
    event OpChallengePeriodUpdated(
        address indexed caller,
        uint16 oldOpChallengePeriod,
        uint16 newOpChallengePeriod
    );

    /// @notice Optimistically pokes the oracle.
    /// @dev Expects `pokeData`'s age to be greater than the timestamp of the
    ///      last successful poke.
    /// @dev Expects `ecdsaData` to be a signature from a feed.
    /// @dev Expects `ecdsaData` to prove the integrity of the `pokeData` and
    ///      `schnorrData`.
    /// @dev If the `schnorrData` is proven to be invalid via the opChallenge
    ///      function, the `ecdsaData` signing feed will be dropped.
    /// @dev Note that the function is payable for gas optimization.
    ///      As the contract is able to receive ETH and pays ETH as bounty for
    ///      invalidating opPokes, there is no risk of ETH being stuck in the
    ///      contract.
    /// @param pokeData The PokeData being poked.
    /// @param schnorrData The SchnorrSignatureData optimistically assumed to be
    ///                    proving the `pokeData`'s integrity.
    /// @param ecdsaData The ECDSASignatureData proving the integrity of the
    ///                  `pokeData` and `schnorrData`.
    function opPoke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData,
        ECDSASignatureData calldata ecdsaData
    ) external payable;

    /// @notice Challenges the current challengeable opPoke.
    /// @dev If opPoke is determined to be invalid, the caller receives an ETH
    ///      bounty. The bounty is the total ETH balance of the contract.
    /// @dev If opPoke is determined to be invalid, the corresponding feed is
    ///      dropped.
    /// @dev Note that the function is payable for gas optimization.
    ///      As the contract is able to receive ETH and pays ETH as bounty for
    ///      invalidating opPokes, there is no risk of ETH being stuck in the
    ///      contract.
    /// @dev Expects a challengeable opPoke.
    /// @dev Expects arguments to match initial opPoke arguments.
    /// @param schnorrData The SchnorrSignatureData initially provided via
    ///                    opPoke.
    function opChallenge(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) external payable;

    /// @notice Returns the feed's address of the last opPoke.
    /// @return The feed's address of the last opPoke.
    function opFeed() external view returns (address);

    /// @notice Returns the commitment of the last opPoke.
    /// @return The last opPoke's commitment.
    function opCommitment() external view returns (bytes32);

    /// @notice Returns the opChallengePeriod security parameter.
    /// @return The opChallengePeriod security parameter.
    function opChallengePeriod() external view returns (uint16);

    /// @notice Updates the opChallengePeriod security parameter.
    /// @dev Only callable by auth'ed address.
    /// @dev Reverts if opChallengePeriod is zero.
    /// @param opChallengePeriod The value to update opChallengePeriod to.
    function setOpChallengePeriod(uint16 opChallengePeriod) external;
}
