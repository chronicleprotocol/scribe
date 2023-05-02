pragma solidity ^0.8.16;

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

interface IScribe {
    /// @dev PokeData encapsulates a value and its age.
    struct PokeData {
        uint128 val;
        uint32 age;
    }

    /// @dev SchnorrData encapsulates a (aggregated) Schnorr signature.
    ///      Schnorr signatures are used to prove a PokeData's integrity.
    struct SchnorrData {
        bytes32 signature;
        address commitment;
        bytes signersBlob;
    }

    /// @dev ECDSAData encapsulates an ECDSA signature.
    struct ECDSAData {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Thrown if a poked value's age is not greater than the oracle's
    ///         current value's age.
    /// @param givenAge The poked value's age.
    /// @param currentAge The oracle's current value's age.
    error StaleMessage(uint32 givenAge, uint32 currentAge);

    /// @notice Thrown if a poked value's age is greater than the current
    ///         time.
    /// @param givenAge The poked value's age.
    /// @param currentTimestamp The current time.
    error FutureMessage(uint32 givenAge, uint32 currentTimestamp);

    /// @notice Thrown if Schnorr signature not signed by exactly bar many
    ///         signers.
    /// @param numberSigners The number of signers for given Schnorr signature.
    /// @param bar The bar security parameter.
    error BarNotReached(uint8 numberSigners, uint8 bar);

    /// @notice Thrown if signature signed by non-feed.
    /// @param signer The signer's address not being a feed.
    error SignerNotFeed(address signer);

    /// @notice Thrown if signer indexes are not encoded so that their
    ///         addresses are in ascending order.
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
    /// @param index The feed's index identifier.
    event FeedLifted(address indexed caller, address indexed feed, uint index);

    /// @notice Emitted when feed dropped.
    /// @param caller The caller's address.
    /// @param feed The feed address dropped.
    /// @param index The feed's index identifier.
    event FeedDropped(address indexed caller, address indexed feed, uint index);

    /// @notice Emitted when bar updated.
    /// @param caller The caller's address.
    /// @param oldBar The old bar's value.
    /// @param newBar The new bar's value.
    event BarUpdated(address indexed caller, uint8 oldBar, uint8 newBar);

    /// @notice Returns the oracle's identifier.
    /// @return wat The oracle's identifier.
    function wat() external view returns (bytes32 wat);

    /// @notice Returns the oracle's identifier message.
    /// @dev This message must be signed by a feed in order to be lifted.
    /// @return watMessage The oracle's identifier message.
    function watMessage() external view returns (bytes32 watMessage);

    /// @notice The maximum number of feed lifts supported.
    /// @dev Note that the constraint comes from feed's indexes being encoded as
    ///      uint8 in SchnorrData.signersBlob.
    /// @return maxFeeds The maximum number of feed lifts supported.
    function maxFeeds() external view returns (uint maxFeeds);

    /// @notice Returns the bar security parameter.
    // @return bar The bar security parameter.
    function bar() external view returns (uint8 bar);

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
    ///      See `verifySchnorrSignature(PokeData,SchnorrData)(bool,bytes)`.
    /// @param pokeData The PokeData being poked.
    /// @param schnorrData The SchnorrData proving the `pokeData`'s
    ///                    integrity.
    function poke(PokeData calldata pokeData, SchnorrData calldata schnorrData)
        external;

    /// @notice Returns whether `message`'s integrity is proven via
    ///         `schnorrData`.
    /// @dev Expects `schnorrData`'s signature to be signed by exactly bar many
    ///      feeds.
    /// @param message The message expected to be signed via `schnorrData`.
    /// @param schnorrData The SchnorrData to verify whether it proves
    ///                    the `message`'s integrity.
    /// @return ok True if `message`'s integrity proven via `schnorrData`,
    ///            false otherwise.
    /// @return err Null if `message`'s integrity proven via `schnorrData`,
    ///             abi-encoded custom error otherwise.
    function verifySchnorrSignature(
        bytes32 message,
        SchnorrData calldata schnorrData
    ) external returns (bool ok, bytes memory err);

    /// @notice Returns the message expected to be signed via Schnorr for
    ///         `pokeData`.
    /// @dev The message is defined as:
    ///         H(tag ‖ H(wat ‖ pokeData)), where H() is the keccak256 function.
    /// @param pokeData The pokeData to create the message for.
    /// @return Message for `pokeData`.
    function constructPokeMessage(PokeData calldata pokeData)
        external
        view
        returns (bytes32);

    /// @notice Returns whether address `who` is a feed and its feed index
    ///         identifier.
    /// @param who The address to check.
    /// @return isFeed True if `who` is feed, false otherwise.
    /// @return feedIndex Non-zero if `who` is feed, zero otherwise.
    function feeds(address who)
        external
        view
        returns (bool isFeed, uint feedIndex);

    /// @notice Returns whether feedIndex `index` maps to a feed and, if so,
    ///         the feed's address.
    /// @param index The feedIndex to check.
    /// @return isFeed True if `index` maps to a feed, false otherwise.
    /// @return feed Address of the feed with feedIndex `index` if `index` maps
    ///              to feed, zero-address otherwise.
    function feeds(uint index)
        external
        view
        returns (bool isFeed, address feed);

    /// @notice Returns list of feed addresses and their index identifiers.
    /// @return feeds List of feed addresses.
    /// @return feedIndexes List of feed's indexes.
    function feeds()
        external
        view
        returns (address[] memory feeds, uint[] memory feedIndexes);

    /// @notice Lifts public key `pubKey` to being a feed.
    /// @dev Only callable by auth'ed address.
    /// @dev The message expected to be signed by `ecdsaData` is defined as via
    ///      `watMessage()(bytes32)` function.
    /// @param pubKey The public key of the feed.
    /// @param ecdsaData ECDSA signed message by the feed's public key.
    /// @return The feed index of the newly lifted feed.
    function lift(LibSecp256k1.Point memory pubKey, ECDSAData memory ecdsaData)
        external
        returns (uint);

    /// @notice Lifts public keys `pubKeys` to being feeds.
    /// @dev Only callable by auth'ed address.
    /// @dev The message expected to be signed by `ecdsaDatas` is defined as via
    ///      `watMessage()(bytes32)` function.
    /// @param pubKeys The public keys of the feeds.
    /// @param ecdsaDatas ECDSA signed message by the feeds' public keys.
    /// @return List of feed indexes of the newly lifted feeds.
    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        ECDSAData[] memory ecdsaDatas
    ) external returns (uint[] memory);

    /// @notice Drops feed with index `feedIndex` from being a feed.
    /// @dev Only callable by auth'ed address.
    /// @param feedIndex The feed index identifier of the feed to drop.
    function drop(uint feedIndex) external;

    /// @notice Drops feeds with indexes `feedIndexes` from being feeds.
    /// @dev Only callable by auth'ed address.
    /// @param feedIndexes The feed's index identifiers of the feeds to drop.
    function drop(uint[] memory feedIndexes) external;

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
