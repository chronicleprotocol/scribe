pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "./IScribe.sol";
import {IScribeAuth} from "./IScribeAuth.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

contract Scribe is IScribe, IScribeAuth, Auth, Toll {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    bytes32 public constant wat = "ETH/USD";

    PokeData internal _pokeData;

    mapping(address => LibSecp256k1.Point) internal _feeds;
    address[] internal _feedsTouched;

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
            assembly ("memory-safe") {
                let size := mload(err)
                let offset := add(err, 0x20)
                revert(offset, size)
            }
        }

        // Store given pokeData in _pokeData storage.
        _pokeData.val = pokeData.val;
        _pokeData.age = uint32(block.timestamp);

        // @todo Test for event emission.
        emit Poked(msg.sender, pokeData.val, uint32(block.timestamp));
    }

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

        address lastSigner;
        address signer = schnorrData.signers[0];
        LibSecp256k1.Point memory signerPubKey = _feeds[signer];

        // Let aggPubKey be the sum of already processed signers' public keys.
        LibSecp256k1.JacobianPoint memory aggPubKey = signerPubKey.toJacobian();

        // Expect signer to be feed by verifying their public key is non-zero.
        if (signerPubKey.isZeroPoint()) {
            bytes memory err = abi.encodeWithSelector(
                IScribe.SignerNotFeed.selector, signer
            );

            return (false, err);
        }

        for (uint i = 1; i < schnorrData.signers.length; i++) {
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
                // @todo Remove by expecting signed message when feed added.
                //       This should prevent this situation to ever occur.
                // @todo return err.
                break;
            }

            aggPubKey.addAffinePoint(signerPubKey);
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
            schnorrMessage,
            schnorrData.signature,
            schnorrData.commitment
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

    function read() external view virtual toll returns (uint) {
        uint val = _pokeData.val;
        require(val != 0);
        return val;
    }

    function tryRead() external view virtual toll returns (bool, uint) {
        uint val = _pokeData.val;
        return (val != 0, val);
    }

    // legacy version.
    function peek() external view virtual toll returns (uint, bool) {
        uint val = _pokeData.val;
        return (val, val != 0);
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function feeds(address who) external view returns (bool) {
        return !_feeds[who].isZeroPoint();
    }

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

    function lift(LibSecp256k1.Point memory pubKey) external auth {
        require(!pubKey.isZeroPoint());

        address feed = pubKey.toAddress();

        if (_feeds[feed].isZeroPoint()) {
            emit FeedLifted(msg.sender, feed);
            _feeds[feed] = pubKey;
            _feedsTouched.push(feed);
        }
    }

    function lift(LibSecp256k1.Point[] memory pubKeys) external auth {
        for (uint i; i < pubKeys.length; i++) {
            require(!pubKeys[i].isZeroPoint());

            address feed = pubKeys[i].toAddress();

            if (_feeds[feed].isZeroPoint()) {
                emit FeedLifted(msg.sender, feed);
                _feeds[feed] = pubKeys[i];
                _feedsTouched.push(feed);
            }
        }
    }

    function drop(LibSecp256k1.Point memory pubKey) external auth {
        _drop(pubKey);
    }

    function _drop(LibSecp256k1.Point memory pubKey) internal virtual {
        address feed = pubKey.toAddress();

        if (!_feeds[feed].isZeroPoint()) {
            emit FeedDropped(msg.sender, feed);
            delete _feeds[feed];
        }
    }

    function drop(LibSecp256k1.Point[] memory pubKeys) external auth {
        _drop(pubKeys);
    }

    function _drop(LibSecp256k1.Point[] memory pubKeys) internal virtual {
        for (uint i; i < pubKeys.length; i++) {
            address feed = pubKeys[i].toAddress();

            if (!_feeds[feed].isZeroPoint()) {
                emit FeedDropped(msg.sender, feed);
                delete _feeds[feed];
            }
        }
    }

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

    /*//////////////////////////////////////////////////////////////
                       OVERRIDDEN TOLL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function toll_auth() internal override(Toll) auth {}
}
