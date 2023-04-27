pragma solidity ^0.8.16;

import {IScribe} from "./IScribe.sol";

interface IScribeOptimistic is IScribe {
    /// @notice Thrown if attempted to opPoke while a previous opPoke is still
    ///         in challenge period.
    error InChallengePeriod();

    /// @notice Thrown if opChallenge called while no opPoke exists thats
    ///         challengeable.
    error NoOpPokeToChallenge();

    /// @notice Thrown if opChallenge called with SchnorrData not matching
    ///         opPoke's SchnorrData.
    /// @param gotHash The truncated keccak256 hash of the SchnorrData argument.
    /// @param wantHash The truncated expected keccak256 hash of the SchnorrData
    ///                 argument.
    error SchnorrDataMismatch(uint160 gotHash, uint160 wantHash);

    /// @notice Emitted when oracles was successfully opPoked.
    /// @param caller The caller's address.
    /// @param opFeed The feed that signed the opPoke.
    /// @param schnorrData The schnorrData
    /// @param pokeData todo
    event OpPoked(
        address indexed caller,
        address indexed opFeed,
        IScribe.SchnorrData schnorrData,
        IScribe.PokeData pokeData
    );

    /// @notice Emitted when successfully challenged an opPoke.
    /// @param caller The caller's address.
    /// @param schnorrErr The abi-encoded custom error returned from the failed
    ///                   Schnorr signature verification.
    event OpPokeChallengedSuccessfully(
        address indexed caller, bytes schnorrErr
    );

    /// @notice Emitted when unsuccessfully challenged an opPoke.
    /// @param caller The caller's address.
    event OpPokeChallengedUnsuccessfully(address indexed caller);

    /// @notice Emitted when ETH reward paid for successfully challenging an
    ///         opPoke.
    /// @param challenger The challenger to which the reward was send.
    /// @param reward The ETH rewards paid.
    event OpChallengeRewardPaid(address indexed challenger, uint reward);

    /// @notice Emitted when an opPoke dropped.
    /// @dev opPoke's are dropped if security parameters are updated that could
    ///      lead to an initially valid opPoke becoming invalid or an opPoke was
    ///      was successfully challenged.
    /// @param caller The caller's address.
    /// @param pokeData The pokeData dropped.
    event OpPokeDataDropped(address indexed caller, IScribe.PokeData pokeData);

    /// @notice Emitted when length of opChallengePeriod updated.
    /// @param caller The caller's address.
    /// @param oldOpChallengePeriod The old opChallengePeriod's length.
    /// @param newOpChallengePeriod The new opChallengePeriod's length.
    event OpChallengePeriodUpdated(
        address indexed caller,
        uint16 oldOpChallengePeriod,
        uint16 newOpChallengePeriod
    );

    /// @notice Emitted when maxChallengeReward updated.
    /// @param caller The caller's address.
    /// @param oldMaxChallengeReward The old maxChallengeReward.
    /// @param newMaxChallengeReward The new maxChallengeReward.
    event MaxChallengeRewardUpdated(
        address indexed caller,
        uint oldMaxChallengeReward,
        uint newMaxChallengeReward
    );

    /// @notice Optimistically pokes the oracle.
    /// @dev Expects `pokeData`'s age to be greater than the timestamp of the
    ///      last successful poke.
    /// @dev Expects `ecdsaData` to be a signature from a feed.
    /// @dev Expects `ecdsaData` to prove the integrity of the `pokeData` and
    ///      `schnorrData`.
    /// @dev If the `schnorrData` is proven to be invalid via the opChallenge
    ///      function, the `ecdsaData` signing feed will be dropped.
    /// @param pokeData The PokeData being poked.
    /// @param schnorrData The SchnorrData optimistically assumed to be
    ///                    proving the `pokeData`'s integrity.
    /// @param ecdsaData The ECDSAData proving the integrity of the
    ///                  `pokeData` and `schnorrData`.
    function opPoke(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData,
        ECDSAData calldata ecdsaData
    ) external;

    /// @notice Challenges the current challengeable opPoke.
    /// @dev If opPoke is determined to be invalid, the caller receives an ETH
    ///      bounty. The bounty is defined via the `challengeReward()(uint)`
    ///      function.
    /// @dev If opPoke is determined to be invalid, the corresponding feed is
    ///      dropped.
    /// @param schnorrData The SchnorrData initially provided via
    ///                    opPoke.
    /// @return True if opPoke declared invalid, false otherwise.
    function opChallenge(SchnorrData calldata schnorrData)
        external
        returns (bool);

    /// @notice Returns the message expected to be signed via ECDSA for calling
    ///         opPoke.
    /// @dev The message is defined as:
    ///         H(tag ‖ H(wat ‖ pokeData ‖ schnorrData)), where H() is the keccak256 function.
    /// @param pokeData The pokeData being optimistically poked.
    /// @param schnorrData The schnorrData proving `pokeData`'s integrity.
    /// @return Message to be signed for an opPoke for `pokeData` and
    ///         `schnorrData`.
    function constructOpPokeMessage(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData
    ) external view returns (bytes32);

    /// @notice Returns the feed index of the feed last opPoke'd.
    /// @return Feed index of the feed last opPoke'd.
    function opFeedIndex() external view returns (uint8);

    /// @notice Returns the opChallengePeriod security parameter.
    /// @return The opChallengePeriod security parameter.
    function opChallengePeriod() external view returns (uint16);

    /// @notice Returns the maxChallengeRewards parameter.
    /// @return The maxChallengeRewards parameter.
    function maxChallengeReward() external view returns (uint);

    /// @notice Returns the ETH rewards being paid for successfully challenging
    ///         an opPoke.
    /// @return The ETH reward for successfully challenging an opPoke.
    function challengeReward() external view returns (uint);

    /// @notice Updates the opChallengePeriod security parameter.
    /// @dev Only callable by auth'ed address.
    /// @dev Reverts if opChallengePeriod is zero.
    /// @param opChallengePeriod The value to update opChallengePeriod to.
    function setOpChallengePeriod(uint16 opChallengePeriod) external;

    /// @notice Updates the maxChallengeReward parameter.
    /// @dev Only callable by auth'ed address.
    /// @param maxChallengeReward The value to update maxChallengeReward to.
    function setMaxChallengeReward(uint maxChallengeReward) external;
}
