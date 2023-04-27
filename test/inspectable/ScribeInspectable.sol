pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "src/IScribe.sol";

import {LibSchnorr} from "src/libs/LibSchnorr.sol";
import {LibSecp256k1} from "src/libs/LibSecp256k1.sol";
import {LibSchnorrData} from "src/libs/LibSchnorrData.sol";

/**
 * @dev Scribe version providing functions to inspect internal state.
 */
contract ScribeInspectable is IScribe, Auth, Toll {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSchnorrData for SchnorrData;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev The maximum number of feed lifts supported.
    ///      Note that this constraint is due to feed's indexes being encoded as
    ///      uint8 in SchnorrData.signersBlob.
    uint public constant maxFeeds = type(uint8).max - 1;

    //--------------------------------------------------------------------------
    // Immutables

    /// @dev The storage slot of _pubKeys[0].
    uint private immutable SLOT_pubKeys;

    /// @inheritdoc IScribe
    bytes32 public immutable wat;

    /// @inheritdoc IScribe
    bytes32 public immutable watMessage;

    //--------------------------------------------------------------------------
    // PokeData Storage

    /// @custom:invariant Only function `poke` may mutate the struct's state.
    ///                     preTx(_pokeData) != postTx(_pokeData)
    ///                         → msg.sig == "poke"
    /// @custom:invariant Field `age` is strictly monotonically increasing.
    ///                     preTx(_pokeDat.age) != postTx(_pokeData.age)
    ///                         → preTx(_pokeData.age) < postTx(_pokeData.age)
    /// @custom:invariant Field `age` may only be mutated to block.timestamp.
    ///                     preTx(_pokeData.age) != postTx(_pokeData.age)
    ///                         → postTx(_pokeData.age) == block.timestamp
    /// @custom:invariant Field `val` can only be read by toll'ed caller.
    PokeData internal _pokeData;

    //--------------------------------------------------------------------------
    // Feeds Storage

    /// @dev List of feeds' public keys.
    /// @custom:invariant Index 0 is zero point.
    ///                     _pubKeys[0].isZeroPoint()
    /// @custom:invariant A non-zero public key exists at most once.
    ///                     ∀x ∊ PublicKeys: x.isZeroPoint() ∨ count(x in _pubKeys) <= 1
    /// @custom:invariant Length is strictly monotonically increasing.
    ///                     preTx(_pubKeys.length) <= posTx(_pubKeys.length)
    /// @custom:invariant Existing public key may only be deleted, never mutated.
    ///                     ∀x ∊ uint: preTx(_pubKeys[x]) != postTx(_pubKeys[x])
    ///                         → postTx(_pubKeys[x].isZeroPoint())
    /// @custom:invariant Newly added public key is non-zero.
    ///                     preTx(_pubKeys.length) != postTx(_pubKeys.length)
    ///                         → postTx(!_pubKeys[_pubKeys.length-1].isZeroPoint())
    /// @custom:invariant Only functions `lift` and `drop` may mutate the array's state.
    ///                     ∀x ∊ uint: preTx(_pubKeys[x]) != postTx(_pubKeys[x])
    ///                         → (msg.sig == "lift" ∨ msg.sig == "drop")
    /// @custom:invariant Array's state may only be mutated by auth'ed caller.
    ///                     ∀x ∊ uint: preTx(_pubKeys[x]) != postTx(_pubKeys[x])
    ///                         → authed(msg.sender)
    LibSecp256k1.Point[] internal _pubKeys;

    /// @dev Mapping of feeds' address to its public key index in _pubKeys.
    /// @custom:invariant Image of mapping is [0, _pubKeys.length).
    ///                     ∀x ∊ Address: _feeds[x] ∊ [0, _pubKeys.length)
    /// @custom:invariant Image of mapping links to feed's public key in _pubKeys.
    ///                     ∀x ∊ Address: _feeds[x] == y and y != 0
    ///                         → _pubKeys[y].toAddress() == x
    /// @custom:invariant Only functions `lift` and `drop` may mutate the mapping's state.
    ///                     ∀x ∊ Address: preTx(_feeds[x]) != postTx(_feeds[x])
    ///                         → (msg.sig == "lift" ∨ msg.sig == "drop")
    /// @custom:invariant Mapping's state may only be mutated by auth'ed caller.
    ///                     ∀x ∊ Address: preTx(_feeds[x]) != postTx(_feeds[x])
    ///                         → authed(msg.sender)
    mapping(address => uint) internal _feeds;

    //--------------------------------------------------------------------------
    // Security Parameters Storage

    /// @inheritdoc IScribe
    /// @dev Note to have as last in storage to enable downstream contracts to
    ///      pack the slot.
    uint8 public bar;

    //--------------------------------------------------------------------------
    // Constructor

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

    //--------------------------------------------------------------------------
    // Poke Functionality

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

    //--------------------------------------------------------------------------
    // Schnorr Signature Verification

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
        // Fail if bar not reached.
        uint numberSigners = schnorrData.getSignerIndexLength();
        if (numberSigners != bar) {
            return (false, _errorBarNotReached(uint8(numberSigners), bar));
        }

        // Load first signerIndex from schnorrData.
        uint signerIndex = schnorrData.getSignerIndex(0);

        // Let signerPubKey be the currently processed signer's public key.
        LibSecp256k1.Point memory signerPubKey;
        signerPubKey = _unsafeLoadPubKeyAt(signerIndex);

        // Let signer be the address of the current signerPubKey.
        address signer = signerPubKey.toAddress();

        // Fail if signer's pubKey is zero point.
        if (signerPubKey.isZeroPoint()) {
            return (false, _errorSignerNotFeed(signer));
        }

        // Let aggPubKey be the sum of already processed signers' public keys.
        // Note that aggPubKey is in Jacobian coordinates.
        LibSecp256k1.JacobianPoint memory aggPubKey;
        aggPubKey = signerPubKey.toJacobian();

        // Iterate over encoded signers. Check each signer's integrity and
        // uniqueness. If signer is valid, aggregate their public key to
        // aggPubKey.
        address lastSigner;
        for (uint i = 1; i < bar; i++) {
            // Cache last processed signer.
            lastSigner = signer;

            // Load next signerIndex from schnorrData.
            signerIndex = schnorrData.getSignerIndex(i);

            // Load next signerPubKey from storage.
            signerPubKey = _unsafeLoadPubKeyAt(signerIndex);

            // Update signer variable.
            signer = signerPubKey.toAddress();

            // Fail if signer's pubKey is zero point.
            if (signerPubKey.isZeroPoint()) {
                return (false, _errorSignerNotFeed(signer));
            }

            // Fail if signers not strictly monotonically increasing.
            // This prevents double signing attacks and enforces strict ordering.
            if (uint160(lastSigner) >= uint160(signer)) {
                return (false, _errorSignersNotOrdered());
            }

            // Having same x coordinates means either double-signing/rogue-key
            // attack or result is Point at Infinity.
            assert(aggPubKey.x != signerPubKey.x);

            // Aggregate signerPubKey by adding it to aggPubKey.
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

    //--------------------------------------------------------------------------
    // Read Functionality

    // @todo Chainlink interface
    // see https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol.

    /// @dev Only callable by toll'ed address.
    function read() external view virtual toll returns (uint) {
        uint val = _pokeData.val;
        require(val != 0);
        return val;
    }

    /// @dev Only callable by toll'ed address.
    function tryRead() external view virtual toll returns (bool, uint) {
        uint val = _pokeData.val;
        return (val != 0, val);
    }

    /// @dev Only callable by toll'ed address.
    function peek() external view virtual toll returns (uint, bool) {
        uint val = _pokeData.val;
        return (val, val != 0);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

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

        // @todo Untested
        LibSecp256k1.Point memory pubKey = _pubKeys[index];
        if (pubKey.isZeroPoint()) {
            return (false, address(0));
        }

        return (true, pubKey.toAddress());
    }

    /// @inheritdoc IScribe
    /// @custom:invariant Result arrays do not contain duplicates.
    ///                     (addrs, indexes) = feeds()
    ///                         →   ∀x ∊ Address: count(x in addrs) <= 1
    ///                           ⋀ ∀y ∊ uint: count(y in indexes) <= 1
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

    //--------------------------------------------------------------------------
    // Auth'ed Functionality

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

    //--------------------------------------------------------------------------
    // Internal Helpers

    /// @dev Halts execution by reverting with `err`.
    function _revert(bytes memory err) internal pure {
        assert(err.length != 0);

        assembly ("memory-safe") {
            let size := mload(err)
            let offset := add(err, 0x20)
            revert(offset, size)
        }
    }

    /// @dev Returns the public key at _pubKeys[index], or zero point if index
    ///      out of bounds.
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

    //--------------------------------------------------------------------------
    // Overridden Toll Functions

    /// @dev Defines the authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}

    //--------------------------------------------------------------------------
    // Inspectable

    function inspectable_pokeData() public view returns (PokeData memory) {
        return _pokeData;
    }

    function inspectable_pubKeys()
        public
        view
        returns (LibSecp256k1.Point[] memory)
    {
        return _pubKeys;
    }

    function inspectable_pubKeys(uint index)
        public
        view
        returns (LibSecp256k1.Point memory)
    {
        return _unsafeLoadPubKeyAt(index);
    }

    function inspectable_feeds(address addr) public view returns (uint) {
        return _feeds[addr];
    }
}
