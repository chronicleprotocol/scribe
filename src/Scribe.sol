pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "./IScribe.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

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

    /// @inheritdoc IScribe
    bytes32 public constant wat = "ETH/USD";

    /// @inheritdoc IScribe
    bytes32 public constant feedLiftMessage =
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", wat));

    PokeData internal _pokeData;

    /// @dev Mapping storing feed addresses to their public keys.
    mapping(address => LibSecp256k1.Point) internal _feeds;

    /// @dev List of addresses possibly being a feed.
    /// @dev May contain duplicates.
    /// @dev May contain addresses not being feed anymore.
    address[] internal _feedsTouched;

    /// @inheritdoc IScribe
    uint8 public bar;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // Note to have an initial bar >1.
        _setBar(2);
    }

    /*//////////////////////////////////////////////////////////////
                           POKE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IScribe
    function poke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) external {
        // Revert if pokeData's age is not fresher than current age.
        if (pokeData.age <= _pokeData.age) {
            revert StaleMessage(pokeData.age, _pokeData.age);
        }

        // Verify schnorrSignatureData.
        bool ok;
        bytes memory err;
        (ok, err) = verifySchnorrSignature(pokeData, schnorrData);

        // Revert with err if verification fails.
        if (!ok) {
            _revert(err);
        }

        // Store given pokeData in _pokeData storage.
        _pokeData.val = pokeData.val;
        _pokeData.age = uint32(block.timestamp);

        emit Poked(msg.sender, pokeData.val, pokeData.age);
    }

    /// @inheritdoc IScribe
    function verifySchnorrSignature(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrData
    ) public view returns (bool, bytes memory) {
        // Expect number of signers to equal bar.
        // @todo Should be == bar to prevent DOS.
        if (schnorrData.signers.length < bar) {
            bytes memory err = abi.encodeWithSelector(
                IScribe.BarNotReached.selector,
                uint8(schnorrData.signers.length),
                bar
            );

            return (false, err);
        }

        // Let signer and signerPubKey be the currently processed signer's
        // address and corresponding public key.
        address signer = schnorrData.signers[0];
        LibSecp256k1.Point memory signerPubKey = _feeds[signer];

        // Let aggPubKey be the sum of already processed signers' public keys.
        LibSecp256k1.JacobianPoint memory aggPubKey = signerPubKey.toJacobian();

        // Expect signer to be feed by verifying their public key is non-zero.
        if (signerPubKey.isZeroPoint()) {
            bytes memory err =
                abi.encodeWithSelector(IScribe.SignerNotFeed.selector, signer);

            return (false, err);
        }

        address lastSigner;
        for (uint i = 1; i < schnorrData.signers.length;) {
            lastSigner = signer;
            signer = schnorrData.signers[i];
            signerPubKey = _feeds[signer];

            // Expect signer to be feed by verifying their public key is
            // non-zero.
            if (signerPubKey.isZeroPoint()) {
                bytes memory err = abi.encodeWithSelector(
                    IScribe.SignerNotFeed.selector, signer
                );

                return (false, err);
            }

            // Expect signers to be ordered to prevent double signing.
            if (uint160(lastSigner) >= uint160(signer)) {
                bytes memory err =
                    abi.encodeWithSelector(IScribe.SignersNotOrdered.selector);

                return (false, err);
            }

            // Either PaI or not mutual inverse.
            if (aggPubKey.x == signerPubKey.x) {
                // @todo Make error type.
                bytes memory err = bytes("ERROR");
                // @todo Remove by expecting signed message when feed added.
                //       This should prevent this situation to ever occur.
                return (false, err);
            }

            // Add signer's public key to the aggregated public key.
            aggPubKey.addAffinePoint(signerPubKey);

            // Unchecked because the maximum length of an array is uint256.
            unchecked {
                i++;
            }
        }

        // Construct Schnorr signed message.
        // @todo Malleability due to encodePacked vs encode?
        bytes32 schnorrMessage = keccak256(
            abi.encode(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                wat
            )
        );

        // Perform signature verification.
        bool ok = aggPubKey.toAffine().verifySignature(
            schnorrMessage, schnorrData.signature, schnorrData.commitment
        );

        // Expect signature verification to succeed.
        if (!ok) {
            bytes memory err =
                abi.encodeWithSelector(IScribe.SchnorrSignatureInvalid.selector);

            return (false, err);
        }

        // Otherwise Schnorr signature is valid.
        return (true, new bytes(0));
    }

    /*//////////////////////////////////////////////////////////////
                           READ FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IScribe
    function feeds(address who) external view returns (bool) {
        return !_feeds[who].isZeroPoint();
    }

    /// @inheritdoc IScribe
    function feeds() external view returns (address[] memory) {
        // Initiate array with upper limit length.
        address[] memory feedsList = new address[](_feedsTouched.length);

        // Iterate through all possible feed addresses.
        uint ctr;
        for (uint i; i < feedsList.length; i++) {
            // Add address only if still feed.
            if (!_feeds[_feedsTouched[i]].isZeroPoint()) {
                feedsList[ctr++] = _feedsTouched[i];
            }
        }

        // Set length of array to number of feeds actually included.
        assembly ("memory-safe") {
            mstore(feedsList, ctr)
        }

        return feedsList;
    }

    /*//////////////////////////////////////////////////////////////
                         AUTH'ED FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IScribe
    function lift(
        LibSecp256k1.Point memory pubKey,
        ECDSASignatureData memory ecdsaData
    ) external auth {
        require(!pubKey.isZeroPoint());

        address feed = pubKey.toAddress();
        address signer =
            ecrecover(feedLiftMessage, ecdsaData.v, ecdsaData.r, ecdsaData.s);

        require(feed == signer);

        if (_feeds[signer].isZeroPoint()) {
            emit FeedLifted(msg.sender, signer);
            _feeds[feed] = pubKey;
            _feedsTouched.push(signer);
        }
    }

    /// @inheritdoc IScribe
    function lift(
        LibSecp256k1.Point[] memory pubKeys,
        ECDSASignatureData[] memory ecdsaDatas
    ) external auth {
        require(pubKeys.length == ecdsaDatas.length);

        for (uint i; i < pubKeys.length; i++) {
            require(!pubKeys[i].isZeroPoint());

            address feed = pubKeys[i].toAddress();
            address signer = ecrecover(
                feedLiftMessage,
                ecdsaDatas[i].v,
                ecdsaDatas[i].r,
                ecdsaDatas[i].s
            );

            require(feed == signer);

            if (_feeds[feed].isZeroPoint()) {
                emit FeedLifted(msg.sender, feed);
                _feeds[feed] = pubKeys[i];
                _feedsTouched.push(feed);
            }
        }
    }

    /// @inheritdoc IScribe
    function drop(LibSecp256k1.Point memory pubKey) external auth {
        _drop(pubKey);
    }

    /// @dev Implemented as virtual internal function to allow downstream
    ///      contracts to overwrite the function.
    function _drop(LibSecp256k1.Point memory pubKey) internal virtual {
        address feed = pubKey.toAddress();

        if (!_feeds[feed].isZeroPoint()) {
            emit FeedDropped(msg.sender, feed);
            delete _feeds[feed];
        }
    }

    /// @inheritdoc IScribe
    function drop(LibSecp256k1.Point[] memory pubKeys) external auth {
        _drop(pubKeys);
    }

    /// @dev Implemented as virtual internal function to allow downstream
    ///      contracts to overwrite the function.
    function _drop(LibSecp256k1.Point[] memory pubKeys) internal virtual {
        for (uint i; i < pubKeys.length; i++) {
            address feed = pubKeys[i].toAddress();

            if (!_feeds[feed].isZeroPoint()) {
                emit FeedDropped(msg.sender, feed);
                delete _feeds[feed];
            }
        }
    }

    /// @inheritdoc IScribe
    function setBar(uint8 bar_) external auth {
        _setBar(bar_);
    }

    /// @dev Implemented as virtual internal function to allow downstream
    ///      contracts to overwrite the function.
    function _setBar(uint8 bar_) internal virtual {
        require(bar_ != 0);

        if (bar != bar_) {
            emit BarUpdated(msg.sender, bar, bar_);
            bar = bar_;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Halts execution by reverting with `err`.
    function _revert(bytes memory err) internal {
        assembly ("memory-safe") {
            let size := mload(err)
            let offset := add(err, 0x20)
            revert(offset, size)
        }
    }

    /*//////////////////////////////////////////////////////////////
                       OVERRIDDEN TOLL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Defines the authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}
