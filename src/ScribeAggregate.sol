pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IScribe} from "./IScribe.sol";
import {IScribeAuth} from "./IScribeAuth.sol";

import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";

/**
 * IMPORTANT: Testing optimizations.
 *            THIS IS NOT THE "PRODUCTION" IMPLEMENTATION!
 *            IT MAY NOT WORK!
 */
contract ScribeAggregate is IScribe, IScribeAuth, Auth, Toll {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point[];
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
                             POKE FUNCTION
    //////////////////////////////////////////////////////////////*/

    function poke(
        PokeData calldata pokeData,
        SchnorrSignatureData calldata schnorrSignatureData
    ) external {
        // Revert if pokeData's age is not fresher than current finalized
        // pokeData's age.
        if (pokeData.age <= _pokeData.age) {
            revert StaleMessage(pokeData.age, _pokeData.age);
        }

        // Revert if number of signers is less than bar.
        if (schnorrSignatureData.signers.length < bar) {
            revert BarNotReached(
                uint8(schnorrSignatureData.signers.length), bar
            );
        }

        // Allocate two points in memory.
        //
        // The first point is in Affine representation and initially used to
        // hold the public key/point of the current signer in the following
        // loop.
        //
        // The second point is in Jacobian representation. It holds the
        // aggregated public key.
        LibSecp256k1.Point memory point;
        LibSecp256k1.JacobianPoint memory jacPoint;

        // Let the current point be the first signer's public key.
        point = _feeds[schnorrSignatureData.signers[0]];

        // Revert if signer is not feed.
        if (point.isZeroPoint()) {
            revert SignerNotFeed(schnorrSignatureData.signers[0]);
        }

        // Let the aggregated public key (in Jacobian representation) be the
        // sum of the signer public keys processed so far.
        jacPoint = point.toJacobian();

        // Iterate over the list of signers. Note to start at index 1 because
        // the first signer is processed already.
        for (uint i = 1; i < schnorrSignatureData.signers.length; i++) {
            address signer = schnorrSignatureData.signers[i];

            // Use point's memory to hold the current signer.
            point = _feeds[signer];

            // Revert if signer is not feed.
            if (point.isZeroPoint()) {
                revert SignerNotFeed(signer);
            }

            // Revert if signers are not in ascending order.
            // Note that this prevents double signing and ensures there exists
            // only one valid sequence of signers for each set of signers.
            uint160 pre = uint160(schnorrSignatureData.signers[i - 1]);
            if (pre >= uint160(signer)) {
                revert SignersNotOrdered();
            }

            if (jacPoint.x == point.x) {
                jacPoint = LibSecp256k1.JacobianPoint(0, 0, 0);
                break;
            }

            // Add the current signer's public key, i.e. the point hold in the
            // point memory allocation, to the aggregated public key.
            // Note that the function stores the result directly inside
            // the jacPoint memory allocation.
            jacPoint.addAffinePoint(point);
        }

        // @todo Further optimize poke via memory tricks?
        // Note that it's possible to further optimize by using intoAffine,
        // which writes into the same memory. Saves around ~100 gas (xD).
        // However, if worth it, could further check to prove/make sure
        // everything is constant memory (I think it is already though).
        point = jacPoint.toAffine();

        // Revert if Schnorr signature verification fails for given pokeData.
        if (
            !point.verifySignature(
                _constructSchnorrMessage(pokeData),
                schnorrSignatureData.signature,
                schnorrSignatureData.commitment
            )
        ) {
            revert SchnorrSignatureInvalid();
        }

        // Store given pokeData in pokeData storage. Note to set the pokeData's
        // age to the current timestamp and NOT the given pokeData's age.
        _pokeData.val = pokeData.val;
        _pokeData.age = uint32(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                         TOLLED VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function read() external view virtual toll returns (uint) {
        uint val = _pokeData.val;
        require(val != 0);
        return val;
    }

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
                           AUTH'ED FUNCTIONS
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

    function drop(LibSecp256k1.Point[] memory pubKeys) external auth {
        _drop(pubKeys);
    }

    function setBar(uint8 bar_) external auth {
        _setBar(bar_);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _drop(LibSecp256k1.Point memory pubKey) internal virtual {
        address feed = pubKey.toAddress();

        if (!_feeds[feed].isZeroPoint()) {
            emit FeedDropped(msg.sender, feed);
            delete _feeds[feed];
        }
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

    function _setBar(uint8 bar_) internal virtual {
        require(bar_ != 0);

        if (bar != bar_) {
            emit BarUpdated(msg.sender, bar, bar_);
            bar = bar_;
        }
    }

    function _constructSchnorrMessage(PokeData memory pokeData)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                pokeData.val,
                pokeData.age,
                wat
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                       OVERRIDDEN TOLL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function toll_auth() internal override(Toll) auth {}
}
