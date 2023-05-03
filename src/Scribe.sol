pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "./IScribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorrData} from "./libs/LibSchnorrData.sol";

/**
 * @title Scribe
 * @custom:version 0.1.0
 *
 * @notice Efficient Schnorr multi-signature based Oracle
 */
contract Scribe is IScribe, Auth, Toll {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSchnorrData for SchnorrData;

    /// @inheritdoc IScribe
    uint public constant maxFeeds = type(uint8).max - 1;

    /// @dev The storage slot of _pubKeys[0].
    uint private immutable SLOT_pubKeys;

    /// @inheritdoc IScribe
    bytes32 public immutable wat;

    /// @inheritdoc IScribe
    bytes32 public immutable watMessage;

    // -- Storage --

    /// @dev Scribe's current value and corresponding age.
    PokeData internal _pokeData;

    /// @dev List of feeds' public keys.
    LibSecp256k1.Point[] internal _pubKeys;

    /// @dev Mapping of feeds' addresses to their public key indexes in
    ///      _pubKeys.
    mapping(address => uint) internal _feeds;

    /// @inheritdoc IScribe
    /// @dev Note to have as last in storage to enable downstream contracts to
    ///      pack the slot.
    uint8 public bar;

    // -- Constructor --

    constructor(bytes32 wat_) {
        require(wat_ != 0);

        // Set wat immutables.
        wat = wat_;
        watMessage =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", wat));

        // Let initial bar be 2.
        _setBar(2);

        // Let _pubKeys[0] be the zero point.
        _pubKeys.push(LibSecp256k1.ZERO_POINT());

        // Let SLOT_pubKeys be _pubKeys[0].slot.
        uint pubKeysSlot;
        assembly ("memory-safe") {
            mstore(0x00, _pubKeys.slot)
            pubKeysSlot := keccak256(0x00, 0x20)
        }
        SLOT_pubKeys = pubKeysSlot;
    }

    // -- Poke Functionality --

    /// @inheritdoc IScribe
    function poke(PokeData calldata pokeData, SchnorrData calldata schnorrData)
        external
    {
        _poke(pokeData, schnorrData);
    }

    /// @dev Optimized function selector: 0x00000082.
    ///      Note that this function is _not_ defined via the IScribe interface
    ///      and one should _not_ depend on it.
    function poke_optimized_7136211(
        PokeData calldata pokeData,
        SchnorrData calldata schnorrData
    ) external {
        _poke(pokeData, schnorrData);
    }

    function _poke(PokeData calldata pokeData, SchnorrData calldata schnorrData)
        private
    {
        // Revert if pokeData is stale.
        if (pokeData.age <= _pokeData.age) {
            revert StaleMessage(pokeData.age, _pokeData.age);
        }
        // Revert if pokeData is from the future.
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
                keccak256(
                    abi.encodePacked(
                        wat, abi.encodePacked(pokeData.val, pokeData.age)
                    )
                )
            )
        );
    }

    // -- Schnorr Signature Verification --

    /// @inheritdoc IScribe
    function verifySchnorrSignature(
        bytes32 message,
        SchnorrData calldata schnorrData
    ) external view returns (bool, bytes memory) {
        return _verifySchnorrSignature(message, schnorrData);
    }

    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Does not run into an infinite loop.
    function _verifySchnorrSignature(
        bytes32 message,
        SchnorrData calldata schnorrData
    ) internal view returns (bool, bytes memory) {
        // Let signerIndex be the current signer's index read from schnorrData.
        uint signerIndex;
        // Let signerPubKey be the public key stored for signerIndex.
        LibSecp256k1.Point memory signerPubKey;
        // Let signer be the address of signerPubKey.
        address signer;
        // Let lastSigner be the previous processed signer.
        address lastSigner;
        // Let aggPubKey be the sum of processed signers' public keys.
        // Note that Jacobian coordinates are used.
        LibSecp256k1.JacobianPoint memory aggPubKey;

        // Fail if bar not reached.
        uint numberSigners = schnorrData.getSignerIndexLength();
        if (numberSigners != bar) {
            return (false, _errorBarNotReached(uint8(numberSigners), bar));
        }

        // Initiate signer variables with schnorrData's 0's signer index.
        signerIndex = schnorrData.getSignerIndex(0);
        signerPubKey = _unsafeLoadPubKeyAt(signerIndex);
        signer = signerPubKey.toAddress();

        // Fail if signer not feed.
        if (signerPubKey.isZeroPoint()) {
            return (false, _errorSignerNotFeed(signer));
        }

        // Initiate aggPubKey with being the signerPubKey.
        aggPubKey = signerPubKey.toJacobian();

        // Aggregate remaining encoded signers.
        for (uint i = 1; i < bar; i++) {
            // Update Signer Variables.
            lastSigner = signer;
            signerIndex = schnorrData.getSignerIndex(i);
            signerPubKey = _unsafeLoadPubKeyAt(signerIndex);
            signer = signerPubKey.toAddress();

            // Fail if signer not feed.
            if (signerPubKey.isZeroPoint()) {
                return (false, _errorSignerNotFeed(signer));
            }

            // Fail if signers not strictly monotonically increasing.
            // This prevents double signing attacks and enforces strict ordering.
            if (uint160(lastSigner) >= uint160(signer)) {
                return (false, _errorSignersNotOrdered());
            }

            assert(aggPubKey.x != signerPubKey.x); // Indicates rogue-key attack

            // Update aggPubKey.
            aggPubKey.addAffinePoint(signerPubKey);
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

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function read() external view virtual toll returns (uint) {
        uint val = _pokeData.val;
        require(val != 0);
        return val;
    }

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function tryRead() external view virtual toll returns (bool, uint) {
        uint val = _pokeData.val;
        return (val != 0, val);
    }

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function peek() external view virtual toll returns (uint, bool) {
        uint val = _pokeData.val;
        return (val, val != 0);
    }

    // - Chainlink Compatibility

    /// @inheritdoc IScribe
    /// @dev Only callable by toll'ed address.
    function latestRoundData()
        external
        view
        toll
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        )
    {
        uint val = _pokeData.val;
        assembly ("memory-safe") {
            answer := val
        }
        updatedAt = _pokeData.age;

        // Set explicitly to zero to silence solc warnings.
        roundId = 0;
        startedAt = 0;
        answeredInRound = 0;
    }

    // -- Public Read Functionality --

    /// @inheritdoc IScribe
    function feeds(address who) external view returns (bool, uint) {
        uint index = _feeds[who];
        assert(index != 0 ? !_pubKeys[index].isZeroPoint() : true);
        return (index != 0, index);
    }

    /// @inheritdoc IScribe
    function feeds(uint index) external view returns (bool, address) {
        if (index >= _pubKeys.length) {
            return (false, address(0));
        }

        LibSecp256k1.Point memory pubKey = _pubKeys[index];
        if (pubKey.isZeroPoint()) {
            return (false, address(0));
        }

        return (true, pubKey.toAddress());
    }

    /// @inheritdoc IScribe
    function feeds() external view returns (address[] memory, uint[] memory) {
        // Initiate arrays with upper limit length.
        uint upperLimitLength = _pubKeys.length;
        address[] memory feedsList = new address[](upperLimitLength);
        uint[] memory feedsIndexesList = new uint[](upperLimitLength);

        // Iterate over feeds' public keys. If a public key is non-zero, their
        // corresponding address is a feed.
        uint ctr;
        LibSecp256k1.Point memory pubKey;
        address feed;
        uint feedIndex;
        for (uint i; i < upperLimitLength; i++) {
            pubKey = _pubKeys[i];

            if (!pubKey.isZeroPoint()) {
                feed = pubKey.toAddress();
                assert(feed != address(0));

                feedIndex = _feeds[feed];
                assert(feedIndex != 0);

                feedsList[ctr] = feed;
                feedsIndexesList[ctr] = feedIndex;

                ctr++;
            }
        }

        // Set length of arrays to number of feeds actually included.
        assembly ("memory-safe") {
            mstore(feedsList, ctr)
            mstore(feedsIndexesList, ctr)
        }

        return (feedsList, feedsIndexesList);
    }

    // -- Auth'ed Functionality --

    /// @inheritdoc IScribe
    function lift(LibSecp256k1.Point memory pubKey, ECDSAData memory ecdsaData)
        external
        auth
        returns (uint)
    {
        return _lift(pubKey, ecdsaData);
    }

    /// @inheritdoc IScribe
    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        ECDSAData[] memory ecdsaDatas
    ) external auth returns (uint[] memory) {
        require(pubKeys.length == ecdsaDatas.length);

        uint[] memory indexes = new uint[](pubKeys.length);
        for (uint i; i < pubKeys.length; i++) {
            indexes[i] = _lift(pubKeys[i], ecdsaDatas[i]);
        }

        // Note that indexes contains duplicates iff duplicate pubKeys provided.
        return indexes;
    }

    function _lift(LibSecp256k1.Point memory pubKey, ECDSAData memory ecdsaData)
        private
        returns (uint)
    {
        address feed = pubKey.toAddress();
        assert(feed != address(0));

        // forgefmt: disable-next-item
        address recovered = ecrecover(
            watMessage,
            ecdsaData.v,
            ecdsaData.r,
            ecdsaData.s
        );
        require(feed == recovered);

        uint index = _feeds[feed];
        if (index == 0) {
            _pubKeys.push(pubKey);
            index = _pubKeys.length - 1;
            _feeds[feed] = index;

            emit FeedLifted(msg.sender, feed, index);
        }
        require(index <= maxFeeds);

        return index;
    }

    /// @inheritdoc IScribe
    function drop(uint feedIndex) external auth {
        _drop(msg.sender, feedIndex);
    }

    /// @inheritdoc IScribe
    function drop(uint[] memory feedIndexes) external auth {
        for (uint i; i < feedIndexes.length; i++) {
            _drop(msg.sender, feedIndexes[i]);
        }
    }

    /// @dev Implemented as virtual internal to allow downstream contracts to
    ///      overwrite the function.
    function _drop(address caller, uint feedIndex) internal virtual {
        require(feedIndex < _pubKeys.length);
        address feed = _pubKeys[feedIndex].toAddress();

        if (_feeds[feed] != 0) {
            emit FeedDropped(caller, feed, _feeds[feed]);

            _feeds[feed] = 0;
            _pubKeys[feedIndex] = LibSecp256k1.ZERO_POINT();
        }
    }

    /// @inheritdoc IScribe
    function setBar(uint8 bar_) external auth {
        _setBar(bar_);
    }

    /// @dev Implemented as virtual internal to allow downstream contracts to
    ///      overwrite the function.
    function _setBar(uint8 bar_) internal virtual {
        require(bar_ != 0);

        if (bar != bar_) {
            emit BarUpdated(msg.sender, bar, bar_);
            bar = bar_;
        }
    }

    // -- Internal Helpers --

    /// @dev Halts execution by reverting with `err`.
    function _revert(bytes memory err) internal pure {
        assert(err.length != 0);

        assembly ("memory-safe") {
            let size := mload(err)
            let offset := add(err, 0x20)
            revert(offset, size)
        }
    }

    /// @dev Returns the public key at `_pubKeys[index]`, or zero point if
    ///      `index` out of bounds.
    function _unsafeLoadPubKeyAt(uint index)
        private
        view
        returns (LibSecp256k1.Point memory)
    {
        // Push immutable to stack as accessing through assembly not supported.
        uint slotPubKeys = SLOT_pubKeys;

        LibSecp256k1.Point memory pubKey;
        assembly ("memory-safe") {
            // Note that a pubKey consists of two words.
            let realIndex := mul(index, 2)

            // Compute slot of _pubKeys[index].
            let slot := add(slotPubKeys, realIndex)

            // Load _pubKeys[index]'s coordinates to stack.
            let x := sload(slot)
            let y := sload(add(slot, 1))

            // Store coordinates in pubKey memory location.
            mstore(pubKey, x)
            mstore(add(pubKey, 0x20), y)
        }

        assert(index < _pubKeys.length || pubKey.isZeroPoint());

        // Note that pubKey is zero if index out of bounds.
        return pubKey;
    }

    function _errorBarNotReached(uint8 got, uint8 want)
        private
        pure
        returns (bytes memory)
    {
        assert(got != want);

        return abi.encodeWithSelector(IScribe.BarNotReached.selector, got, want);
    }

    function _errorSignerNotFeed(address signer)
        private
        view // @todo View due to assert.
        returns (bytes memory)
    {
        assert(_feeds[signer] == 0);

        return abi.encodeWithSelector(IScribe.SignerNotFeed.selector, signer);
    }

    function _errorSignersNotOrdered() private pure returns (bytes memory) {
        return abi.encodeWithSelector(IScribe.SignersNotOrdered.selector);
    }

    function _errorSchnorrSignatureInvalid()
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IScribe.SchnorrSignatureInvalid.selector);
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}
