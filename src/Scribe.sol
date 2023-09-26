// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {console2} from "forge-std/console2.sol";

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "./IScribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorrData} from "./libs/LibSchnorrData.sol";

/**
 * @title Scribe
 * @custom:version 2.0.0
 *
 * @notice Efficient Schnorr multi-signature based Oracle
 */
contract Scribe is IScribe, Auth, Toll {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSchnorrData for SchnorrData;

    /// @inheritdoc IScribe
    uint8 public constant decimals = 18;

    /// @inheritdoc IScribe
    bytes32 public constant feedRegistrationMessage = keccak256(
        abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256("Chronicle Feed Registration")
        )
    );

    /// @inheritdoc IChronicle
    bytes32 public immutable wat;

    // -- Storage --

    /// @dev Scribe's current value and corresponding age.
    PokeData internal _pokeData;

    LibSecp256k1.Point[256] internal _pubKeys;

    /// @inheritdoc IScribe
    /// @dev Note to have as last in storage to enable downstream contracts to
    ///      pack the slot.
    uint8 public bar;

    // -- Constructor --

    constructor(address initialAuthed, bytes32 wat_)
        payable
        Auth(initialAuthed)
    {
        require(wat_ != 0);

        // Set wat immutable.
        wat = wat_;

        // Let initial bar be 2.
        _setBar(2);
    }

    // -- Poke Functionality --

    /// @dev Optimized function selector: 0x00000082.
    ///      Note that this function is _not_ defined via the IScribe interface
    ///      and one should _not_ depend on it.
    function poke_optimized_7136211(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData
    ) external {
        _poke(pokeData, schnorrData);
    }

    /// @inheritdoc IScribe
    function poke(PokeData calldata pokeData, SchnorrData calldata schnorrData)
        external
    {
        _poke(pokeData, schnorrData);
    }

    function _poke(PokeData calldata pokeData, SchnorrData calldata schnorrData)
        internal
        virtual
    {
        // Revert if pokeData stale.
        if (pokeData.age <= _pokeData.age) {
            revert StaleMessage(pokeData.age, _pokeData.age);
        }
        // Revert if pokeData from the future.
        if (pokeData.age > uint32(block.timestamp)) {
            revert FutureMessage(pokeData.age, uint32(block.timestamp));
        }

        // Revert if schnorrData does not prove integrity of pokeData.
        bool ok;
        bytes memory err;
        // forgefmt: disable-next-item
        (ok, err) = _verifySchnorrSignature(
            constructPokeMessage(pokeData),
            schnorrData
        );
        if (!ok) {
            _revert(err);
        }

        // Store pokeData's val in _pokeData storage and set its age to now.
        _pokeData.val = pokeData.val;
        _pokeData.age = uint32(block.timestamp);

        emit Poked(msg.sender, pokeData.val, pokeData.age);
    }

    /// @inheritdoc IScribe
    function constructPokeMessage(PokeData memory pokeData)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked(wat, pokeData.val, pokeData.age))
            )
        );
    }

    // -- Schnorr Signature Verification --

    /// @inheritdoc IScribe
    function isAcceptableSchnorrSignatureNow(
        bytes32 message,
        SchnorrData calldata schnorrData
    ) external view returns (bool) {
        bool ok;
        (ok, /*err*/ ) = _verifySchnorrSignature(message, schnorrData);

        return ok;
    }

    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Runtime is O(bar).
    function _verifySchnorrSignature(
        bytes32 message,
        SchnorrData calldata schnorrData
    ) internal view returns (bool, bytes memory) {
        // Let feedPubKey be the currently processed feed's public key.
        LibSecp256k1.Point memory feedPubKey;
        // Let feedId be the currently processed feed's id.
        uint8 feedId;
        // Let aggPubKey be the sum of processed feeds' public keys.
        // Note that Jacobian coordinates are used.
        LibSecp256k1.JacobianPoint memory aggPubKey;
        // Let bloom be a bloom filter to check for double signing attempts.
        uint bloom;

        // Fail if number feeds unequal to bar.
        //
        // Note that requiring equality constrains the verification's runtime
        // from Ω(bar) to Θ(bar).
        uint numberFeeds = schnorrData.numberFeeds();
        if (numberFeeds != bar) {
            return (false, _errorBarNotReached(uint8(numberFeeds), bar));
        }

        // Initiate feed variables with schnorrData's 0's feed index.
        feedId = schnorrData.loadFeedId(0);
        feedPubKey = _sloadPubKey(feedId);

        // Fail if feed not lifted.
        if (feedPubKey.isZeroPoint()) {
            return (false, _errorInvalidFeedId(feedId));
        }

        // Initiate bloom filter with feedId set.
        bloom = 1 << feedId;

        // Initiate aggPubKey with value of first feed's public key.
        aggPubKey = feedPubKey.toJacobian();

        for (uint8 i = 1; i < bar;) {
            // Update feed variables.
            feedId = schnorrData.loadFeedId(i);
            feedPubKey = _sloadPubKey(feedId);

            // Fail if feed not lifted.
            if (feedPubKey.isZeroPoint()) {
                return (false, _errorInvalidFeedId(feedId));
            }

            // Fail if double signing attempted.
            if (bloom & (1 << feedId) != 0) {
                return (false, _errorDoubleSigningAttempted(feedId));
            }
            // Update bloom filter.
            bloom |= 1 << feedId;

            // assert(aggPubKey.x != feedPubKey.x); // Indicates rogue-key attack

            // Add feedPubKey to already aggregated public keys.
            aggPubKey.addAffinePoint(feedPubKey);

            // forgefmt: disable-next-item
            unchecked { ++i; }
        }

        // Fail if signature verification fails.
        bool ok = aggPubKey.toAffine().verifySignature(
            message, schnorrData.signature, schnorrData.commitment
        );
        if (!ok) {
            return (false, _errorSchnorrSignatureInvalid());
        }

        // Otherwise Schnorr signature is valid.
        return (true, new bytes(0));
    }

    // -- Toll'ed Read Functionality --

    // - IChronicle Functions

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function read() external view virtual toll returns (uint) {
        uint val = _pokeData.val;
        require(val != 0);
        return val;
    }

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function tryRead() external view virtual toll returns (bool, uint) {
        uint val = _pokeData.val;
        return (val != 0, val);
    }

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function readWithAge() external view virtual toll returns (uint, uint) {
        uint val = _pokeData.val;
        uint age = _pokeData.age;
        require(val != 0);
        return (val, age);
    }

    /// @inheritdoc IChronicle
    /// @dev Only callable by toll'ed address.
    function tryReadWithAge()
        external
        view
        virtual
        toll
        returns (bool, uint, uint)
    {
        uint val = _pokeData.val;
        uint age = _pokeData.age;
        return val != 0 ? (true, val, age) : (false, 0, 0);
    }

    // - MakerDAO Compatibility

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function peek() external view virtual toll returns (uint, bool) {
        uint val = _pokeData.val;
        return (val, val != 0);
    }

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function peep() external view virtual toll returns (uint, bool) {
        uint val = _pokeData.val;
        return (val, val != 0);
    }

    // - Chainlink Compatibility

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function latestRoundData()
        external
        view
        virtual
        toll
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 1;
        answer = int(uint(_pokeData.val));
        // assert(uint(answer) == uint(_pokeData.val));
        startedAt = 0;
        updatedAt = _pokeData.age;
        answeredInRound = roundId;
    }

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function latestAnswer() external view virtual toll returns (int) {
        uint val = _pokeData.val;
        return int(val);
    }

    // -- Public Read Functionality --

    /// @inheritdoc IScribe
    function feeds(address who) external view returns (bool, uint8) {
        uint8 feedId = uint8(uint(uint160(who)) >> 152);

        LibSecp256k1.Point memory pubKey = _sloadPubKey(feedId);
        bool isFeed = !pubKey.isZeroPoint() && pubKey.toAddress() == who;

        return (isFeed, feedId);
    }

    /// @inheritdoc IScribe
    function feeds(uint8 feedId) external view returns (bool, address) {
        LibSecp256k1.Point memory pubKey = _sloadPubKey(feedId);

        return pubKey.isZeroPoint()
            ? (false, address(0))
            : (true, pubKey.toAddress());
    }

    /// @inheritdoc IScribe
    function feeds() external view returns (address[] memory, uint8[] memory) {
        // Initiate arrays with upper limit length.
        address[] memory feeds_ = new address[](256);
        uint8[] memory ids = new uint8[](256);

        LibSecp256k1.Point memory pubKey;
        address feed;
        uint8 id;
        uint ctr;

        for (uint i; i < 256;) {
            pubKey = _sloadPubKey(uint8(i));

            if (!pubKey.isZeroPoint()) {
                feed = pubKey.toAddress();
                id = uint8(uint(uint160(feed)) >> 152);

                feeds_[ctr] = feed;
                ids[ctr] = id;

                // forgefmt: disable-next-item
                unchecked { ++ctr; }
            }

            // forgefmt: disable-next-item
            unchecked { ++i; }
        }

        assembly ("memory-safe") {
            mstore(feeds_, ctr)
            mstore(ids, ctr)
        }

        return (feeds_, ids);
    }

    // -- Auth'ed Functionality --

    /// @inheritdoc IScribe
    function lift(LibSecp256k1.Point memory pubKey, ECDSAData memory ecdsaData)
        external
        auth
        returns (uint8)
    {
        return _lift(pubKey, ecdsaData);
    }

    /// @inheritdoc IScribe
    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        ECDSAData[] memory ecdsaDatas
    ) external auth returns (uint8[] memory) {
        require(pubKeys.length == ecdsaDatas.length);

        uint8[] memory feedIds = new uint8[](pubKeys.length);
        for (uint i; i < pubKeys.length;) {
            feedIds[i] = _lift(pubKeys[i], ecdsaDatas[i]);

            // forgefmt: disable-next-item
            unchecked { ++i; }
        }

        return feedIds;
    }

    function _lift(LibSecp256k1.Point memory pubKey, ECDSAData memory ecdsaData)
        internal
        returns (uint8)
    {
        address feed = pubKey.toAddress();
        // assert(feed != address(0));

        // forgefmt: disable-next-item
        address recovered = ecrecover(
            feedRegistrationMessage,
            ecdsaData.v,
            ecdsaData.r,
            ecdsaData.s
        );
        require(feed == recovered);

        uint8 feedId = uint8(uint(uint160(feed)) >> 152);

        LibSecp256k1.Point memory sPubKey = _sloadPubKey(feedId);
        if (sPubKey.isZeroPoint()) {
            _sstorePubKey(feedId, pubKey);

            emit FeedLifted(msg.sender, feed, feedId);
        } else {
            // Note to be idempotent. However, disallow updating an id's feed
            // via lifting without dropping the previous feed.
            require(feed == sPubKey.toAddress());
        }

        return feedId;
    }

    /// @inheritdoc IScribe
    function drop(uint8 feedId) external auth {
        _drop(msg.sender, feedId);
    }

    /// @inheritdoc IScribe
    function drop(uint8[] memory feedIds) external auth {
        for (uint i; i < feedIds.length;) {
            _drop(msg.sender, feedIds[i]);

            // forgefmt: disable-next-item
            unchecked { ++i; }
        }
    }

    function _drop(address caller, uint8 feedId) internal virtual {
        LibSecp256k1.Point memory pubKey = _sloadPubKey(feedId);
        if (!pubKey.isZeroPoint()) {
            _sstorePubKey(feedId, LibSecp256k1.ZERO_POINT());

            emit FeedDropped(caller, pubKey.toAddress(), feedId);
        }
    }

    /// @inheritdoc IScribe
    function setBar(uint8 bar_) external auth {
        _setBar(bar_);
    }

    function _setBar(uint8 bar_) internal virtual {
        require(bar_ != 0);

        if (bar != bar_) {
            emit BarUpdated(msg.sender, bar, bar_);
            bar = bar_;
        }
    }

    // -- Internal Helpers --

    function _sloadPubKey(uint8 index)
        internal
        view
        returns (LibSecp256k1.Point memory)
    {
        LibSecp256k1.Point memory pubKey;
        assembly ("memory-safe") {
            let slot := add(_pubKeys.slot, shl(1, index))

            let x := sload(slot)
            let y := sload(add(slot, 1))

            mstore(pubKey, x)
            mstore(add(pubKey, 32), y)
        }

        // assert(
        //     pubKey.isZeroPoint()
        //         || uint(uint160(pubKey.toAddress())) >> 152 == index
        // );

        return pubKey;
    }

    function _sstorePubKey(uint8 index, LibSecp256k1.Point memory pubKey)
        internal
    {
        // assert(
        //     pubKey.isZeroPoint()
        //         || uint(uint160(pubKey.toAddress())) >> 152 == index
        // );

        assembly ("memory-safe") {
            let slot := add(_pubKeys.slot, shl(1, index))

            let pubKey_x := mload(pubKey)
            let pubKey_y := mload(add(pubKey, 32))

            sstore(slot, pubKey_x)
            sstore(add(slot, 1), pubKey_y)
        }
    }

    function _revert(bytes memory err) internal pure {
        // assert(err.length != 0);
        assembly ("memory-safe") {
            let size := mload(err)
            let offset := add(err, 0x20)
            revert(offset, size)
        }
    }

    function _errorBarNotReached(uint8 got, uint8 want)
        internal
        pure
        returns (bytes memory)
    {
        // assert(got != want);
        return abi.encodeWithSelector(IScribe.BarNotReached.selector, got, want);
    }

    function _errorInvalidFeedId(uint8 feedId)
        internal
        pure
        returns (bytes memory)
    {
        // assert(_sloadPubKey(feedId).isZeroPoint());
        return abi.encodeWithSelector(IScribe.InvalidFeedId.selector, feedId);
    }

    function _errorDoubleSigningAttempted(uint8 feedId)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            IScribe.DoubleSigningAttempted.selector, feedId
        );
    }

    function _errorSchnorrSignatureInvalid()
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IScribe.SchnorrSignatureInvalid.selector);
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 *
 *      For more info, see docs/Deployment.md.
 */
contract Chronicle_BASE_QUOTE_COUNTER is Scribe {
    // @todo       ^^^^ ^^^^^ ^^^^^^^ Adjust name of Scribe instance.
    constructor(address initialAuthed, bytes32 wat_)
        Scribe(initialAuthed, wat_)
    {}
}
