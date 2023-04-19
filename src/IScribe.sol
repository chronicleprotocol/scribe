pragma solidity ^0.8.16;

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

interface IScribe {
    /// @dev PokeData encapsulates a value and its age.
    struct PokeData {
        uint128 val;
        uint32 age;
    }

    /// @dev SchnorrSignatureData encapsulates an aggregated Schnorr signature's
    ///      data. Schnorr signatures are used to prove a PokeData's integrity.
    struct SchnorrSignatureData {
        address[] signers;
        bytes32 signature;
        address commitment;
    }

    /// @dev ECDSASignatureData encapsulates a single ECDSA signature.
    struct ECDSASignatureData {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Thrown if a poked value's age is not greater than the oracle's
    ///         current value's age.
    /// @param givenAge The poked value's age.
    /// @param currentAge The oracle's current value's age.
    error StaleMessage(uint32 givenAge, uint32 currentAge);

    /// @notice Thrown if not signed by exactly bar many signers.
    /// @param numberSigners The number of signers for given signature.
    /// @param bar The bar security parameter.
    error BarNotReached(uint8 numberSigners, uint8 bar);

    /// @notice Thrown if signature signed by non-feed.
    /// @param signer The signer's address not being a feed.
    error SignerNotFeed(address signer);

    /// @notice Thrown if signers not given in ascending order.
    error SignersNotOrdered();

    /// @notice Thrown if Schnorr signature verification failed.
    error SchnorrSignatureInvalid();

    /// @notice Emitted when oracle was successfully poked.
    /// @param caller The caller's address.
    /// @param val The value poked.
    /// @param age The age of the value poked.
    event Poked(address indexed caller, uint128 val, uint32 age);

    /// @notice Emitted when new feed lifted.
    /// @param caller The caller's address.
    /// @param feed The feed address lifted.
    event FeedLifted(address indexed caller, address indexed feed);

    /// @notice Emitted when feed dropped.
    /// @param caller The caller's address.
    /// @param feed The feed address dropped.
    event FeedDropped(address indexed caller, address indexed feed);

    /// @notice Emitted when bar updated.
    /// @param caller The caller's address.
    /// @param oldBar The old bar's value.
    /// @param newBar The new bar's value.
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    /// @notice Returns the oracle's identifier.
    /// @return wat The oracle's identifier.
    function wat() external view returns (bytes32 wat);

    /// @notice Returns the oracle's current value.
    /// @dev Reverts if no value set.
    /// @return value The oracle's current value.
    function read() external view returns (uint value);

    /// @notice Returns the oracle's current value.
    /// @return isValid True if value exists, false otherwise.
    /// @return value The oracle's current value if it exists, zero otherwise.
    function tryRead() external view returns (bool isValid, uint value);

    /// @notice Pokes the oracle.
    /// @dev Expects `pokeData`'s age to be greater than the timestamp of the
    ///      last successful poke.
    /// @dev Expects `schnorrData` to prove `pokeData`'s integrity.
    ///      See `verifySchnorrSignature(PokeData,SchnorrSignatureData)(bool,bytes)`.
    /// @param pokeData The PokeData being poked.
    /// @param schnorrData The SchnorrSignatureData proving the `pokeData`'s
    ///                    integrity.
    function poke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) external;

    /// @notice Returns whether `pokeData`'s integrity is proven via
    ///         `schnorrData`.
    /// @dev Expects `schnorrData`'s signature to be signed by exactly bar many
    ///      feeds.
    /// @param message TODO NatSpec for missing argument
    ///                 `schnorrData`.
    /// @param schnorrData The SchnorrSignatureData to verify whether it proves
    ///                    the `pokeData`'s integrity.
    /// @return ok True if `pokeData`'s integrity proven via `schnorrData`,
    ///            false otherwise.
    /// @return err Null if `pokeData`'s integrity proven via `schnorrData`,
    ///             abi-encoded custom error otherwise.
    function verifySchnorrSignature(
        bytes32 message,
        SchnorrSignatureData calldata schnorrData
    ) external returns (bool ok, bytes memory err);

    // @todo IScribe NatSpec documentation.
    function constructPokeMessage(PokeData calldata pokeData)
        external
        view
        returns (bytes32);

    /// @notice Returns whether address `who` is a feed.
    /// @param who The address to check.
    /// @return isFeed True if `who` is a feed, false otherwise.
    function feeds(address who) external view returns (bool isFeed);

    /// @notice Returns full list of feed addresses.
    /// @dev May contain duplicates.
    /// @return feeds List of feed addresses.
    function feeds() external view returns (address[] memory feeds);

    /// @notice Returns the message to be signed to prove ownership of a public
    ///         key in order to be lifted to a feed.
    /// @return message The message to sign to prove ownership of a public key.
    function feedLiftMessage() external view returns (bytes32 message);

    /// @notice Lifts public key `pubKey` to being a feed.
    /// @dev Only callable by auth'ed address.
    /// @dev The message expected to be signed is defined via the
    ///      `feedLitMessage()(bytes32)` function.
    /// @param pubKey The public key of the feed.
    /// @param ecdsaData ECDSA signed message by the feed's public key.
    function lift(
        LibSecp256k1.Point memory pubKey,
        ECDSASignatureData memory ecdsaData
    ) external;

    /// @notice Lifts public keys `pubKeys` to being feeds.
    /// @dev Only callable by auth'ed address.
    /// @dev The message expected to be signed is defined via the
    ///      `feedLitMessage()(bytes32)` function.
    /// @param pubKeys The public keys of the feeds.
    /// @param ecdsaDatas ECDSA signed message by the feeds' public keys.
    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        ECDSASignatureData[] memory ecdsaDatas
    ) external;

    /// @notice Drops public key `pubKey` from being a feed.
    /// @dev Only callable by auth'ed address.
    /// @param pubKey The public keys of the feed.
    function drop(LibSecp256k1.Point memory pubKey) external;

    /// @notice Drops public keys `pubKeys` from being feeds.
    /// @dev Only callable by auth'ed address.
    /// @param pubKeys The public keys of the feeds.
    function drop(LibSecp256k1.Point[] memory pubKeys) external;

    /// @notice Returns the bar security parameter.
    /// @return bar The bar security parameter.
    function bar() external view returns (uint8 bar);

    /// @notice Updates the bar security parameters to `bar`.
    /// @dev Only callable by auth'ed address.
    /// @dev Reverts if `bar` is zero.
    /// @param bar The value to update bar to.
    function setBar(uint8 bar) external;

    /// @notice Returns the oracle's current value.
    /// @custom:deprecated Use `tryRead()(bool,uint)` instead.
    /// @return value The oracle's current value if it exists, zero otherwise.
    /// @return isValid True if value exists, false otherwise.
    function peek() external view returns (uint value, bool isValid);
}
