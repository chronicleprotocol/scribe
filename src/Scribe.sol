pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "./IScribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorrSignatureData} from "./libs/LibSchnorrSignatureData.sol";

// @todo Invariant tests for storage mutations.
//       based on msg.sender + selector,
//                timestamp + last tx, etc..

/**
 * @title Scribe
 *
 * @notice Schnorr Signatures
 *         Aggregated, strong and true
 *         Delivering the truth
 *         Just for you
 *
 * @dev
 */
contract Scribe is IScribe, Auth, Toll {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using LibSchnorrSignatureData for SchnorrSignatureData;

    /*
    Terms:
        feed = address being whitelisted to participate as signer in Schnorr signature for poke
               Proven to be owner of the address via ECDSA signature check
               Each feed has an immutable index.

        signer = address participating as signer in Schnorr signature for poke
                 MUST be checked whether being feed!

        signerPubKey = public key of signer

        pubKey = Public key, i.e. secp256k1 point
    */

    //--------------------------------------------------------------------------
    // Constants

    uint private immutable SLOT_pubKeys;

    /// @dev The maximum number of feeds supported.
    uint public constant maxFeeds = type(uint8).max - 1;

    //--------------------------------------------------------------------------
    // Immutables

    /// @inheritdoc IScribe
    bytes32 public immutable wat;

    /// @inheritdoc IScribe
    bytes32 public immutable watMessage;

    //--------------------------------------------------------------------------
    // PokeData Storage

    PokeData internal _pokeData;

    //--------------------------------------------------------------------------
    // Feeds Storage

    // List of public keys from lifted feeds.
    // Ownership of private key proven via ECDSA signature.
    // Immutable in that sense that new pubKeys are only appended.
    // If pubKey removed, due to feed being dropped, we keep the hole in the array.
    // Index 0 MUST be zero point.
    // IMPORTANT INVARIANT: NO PUBLIC KEY EXISTS MORE THAN ONCE IN LIST!!!!
    LibSecp256k1.Point[] internal _pubKeys;

    // 0 if not feed. If not 0, image is index in pubKeys array.
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

        // Set wat storage.
        wat = wat_;
        // forgefmt: disable-next-item
        watMessage = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                wat
            )
        );

        // Let initial bar be >1. @todo Why bar must be >1 not just >0?
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

    function poke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) external {
        // Revert if pokeData is stale.
        if (pokeData.age <= _pokeData.age) {
            revert StaleMessage(pokeData.age, _pokeData.age);
        }

        // Construct pokeMessage.
        bytes32 pokeMessage = constructPokeMessage(pokeData);

        // Revert if schnorrData does not verify pokeData.
        bool ok;
        bytes memory err;
        (ok, err) = _verifySchnorrSignature(pokeMessage, schnorrData);
        if (!ok) {
            _revert(err);
        }

        // Store pokeData's val in _pokeData storage and set its age to now.
        _pokeData.val = pokeData.val;
        _pokeData.age = uint32(block.timestamp);

        emit Poked(msg.sender, pokeData.val, pokeData.age);
    }

    function constructPokeMessage(PokeData memory pokeData)
        public
        view
        returns (bytes32)
    {
        // pokeMessage = H(tag ‖ H(wat ‖ pokeData))
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

    function verifySchnorrSignature(
        bytes32 message,
        SchnorrSignatureData calldata schnorrData
    ) external view returns (bool, bytes memory) {
        return _verifySchnorrSignature(message, schnorrData);
    }

    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Does not run into an infinite loop.
    function _verifySchnorrSignature(
        bytes32 message,
        SchnorrSignatureData calldata schnorrData
    ) internal view returns (bool, bytes memory) {
        // Fail if bar not reached.
        uint numberSigners = schnorrData.signerIndexLength();
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
            // Cache the last processed signer.
            lastSigner = signer;

            // @todo Formalize calldata signersBlob.
            //       First signers is in _highest order byte_.
            //       Define encoding mechanism via encodePacked.
            //       Decoding via loop + getByteAtIndex

            // Load next signerIndex from schnorrData.
            signerIndex = schnorrData.getSignerIndex(i);

            // Load next signerPubKey from storage.
            signerPubKey = _unsafeLoadPubKeyAt(signerIndex);

            // Update signer variable.
            signer = signerPubKey.toAddress();

            // @todo Error off.
            // Fail if signer's pubKey is zero point.
            if (signerPubKey.isZeroPoint()) {
                return (false, _errorSignerNotFeed(signer));
            }

            // Fail if signers not strictly monotonically increasing.
            // This prevents double signing attacks and enforces strict ordering.
            if (uint160(lastSigner) >= uint160(signer)) {
                return (false, _errorSignersNotOrdered());
            }

            // If the x coordinates of two points are equal, one of the
            // following cases hold:
            // 1) The two points are equal
            // 2) The sum of the two points is the "Point at Infinity"
            // See slide 24 at https://www.math.brown.edu/johsilve/Presentations/WyomingEllipticCurve.pdf.
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

    // @todo Should peek return non-finalized opPoke if optimistic?
    /// @dev Only callable by toll'ed address.
    function peek() external view virtual toll returns (uint, bool) {
        uint val = _pokeData.val;
        return (val, val != 0);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    function feeds(address who) external view returns (bool, uint) {
        uint index = _feeds[who];
        assert(index != 0 ? !_pubKeys[index].isZeroPoint() : true);
        return (index != 0, index);
    }

    // @todo Can feeds() return duplicates? Don't think so. Check!
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

    // @todo FeedLifted event should have index of feed!
    // @todo FeedDropped event should have index of feed!
    //       -> Invariant: feed index emitted via FeedDropped will never be
    //                     written to again.

    function lift(
        LibSecp256k1.Point memory pubKey,
        ECDSASignatureData memory ecdsaData
    ) external auth returns (uint) {
        return _lift(pubKey, ecdsaData);
    }

    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        ECDSASignatureData[] memory ecdsaDatas
    ) external auth returns (uint[] memory) {
        require(pubKeys.length == ecdsaDatas.length);

        uint[] memory indexes = new uint[](pubKeys.length);
        for (uint i; i < pubKeys.length; i++) {
            indexes[i] = _lift(pubKeys[i], ecdsaDatas[i]);
        }

        // Note that indexes contains duplicates iff duplicate pubKeys provided.
        return indexes;
    }

    function _lift(
        LibSecp256k1.Point memory pubKey,
        ECDSASignatureData memory ecdsaData
    ) private returns (uint) {
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
            emit FeedLifted(msg.sender, feed);

            _pubKeys.push(pubKey);
            index = _pubKeys.length - 1;
            _feeds[feed] = index;
        }

        assert(index <= maxFeeds);

        return index;
    }

    function drop(uint feedIndex) external auth {
        _drop(msg.sender, feedIndex);
    }

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
            emit FeedDropped(caller, feed);

            _feeds[feed] = 0;
            _pubKeys[feedIndex] = LibSecp256k1.ZERO_POINT();
        }
    }

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

    // @todo Rename to just SignatureInvalid?
    function _errorSchnorrSignatureInvalid()
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IScribe.SchnorrSignatureInvalid.selector);
    }

    // @todo doc: unsafe because no index out of bounds check.
    //            Instead just returns zero point if so.
    //            Secure because zero point cannot verify signature.
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
            let realIndex := add(index, index)

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

    //--------------------------------------------------------------------------
    // Overridden Toll Functions

    /// @dev Defines the authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}
