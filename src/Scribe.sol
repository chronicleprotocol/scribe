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
    using LibSecp256k1 for LibSecp256k1.Point[];

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

        // Declare array of secp256k1 points (public keys) with enough capacity
        // to hold each signer's public key.
        LibSecp256k1.Point[] memory pubKeys =
            new LibSecp256k1.Point[](schnorrSignatureData.signers.length);

        // Iterate over the set of signers.
        for (uint i; i < schnorrSignatureData.signers.length; i++) {
            address signer = schnorrSignatureData.signers[i];

            // Revert if signer is not feed.
            if (_feeds[signer].isZeroPoint()) {
                revert SignerNotFeed(signer);
            }

            // Revert if signers are not in ascending order.
            // Note that this prevents double signing and ensures there exists
            // only one valid sequence of signers for each set of signers.
            if (i != 0) {
                uint160 pre = uint160(schnorrSignatureData.signers[i - 1]);
                if (pre >= uint160(signer)) {
                    revert SignersNotOrdered();
                }
            }

            // Add signer's public key to array.
            pubKeys[i] = _feeds[signer];
        }

        // Compute the aggregated public key from the set of signers.
        // @todo Note that the aggregate function iterates over the set of
        //       signers again. Optimizing this is possible but _could_ lead
        //       to problems regarding "separation of concerns".
        LibSecp256k1.Point memory aggPubKey = pubKeys.aggregate();

        // Revert if Schnorr signature verification fails for given pokeData.
        if (
            !aggPubKey.verifySignature(
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

        if (!_feeds[feed].isZeroPoint()) {
            return;
        }

        emit FeedLifted(msg.sender, feed);
        _feeds[feed] = pubKey;
        _feedsTouched.push(feed);
    }

    function lift(LibSecp256k1.Point[] memory pubKeys) external auth {
        for (uint i; i < pubKeys.length; i++) {
            require(!pubKeys[i].isZeroPoint());

            address feed = pubKeys[i].toAddress();

            if (!_feeds[feed].isZeroPoint()) {
                continue;
            }

            emit FeedLifted(msg.sender, feed);
            _feeds[feed] = pubKeys[i];
            _feedsTouched.push(feed);
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

        // @todo Should be idempotent wrt event emission?

        emit FeedDropped(msg.sender, feed);
        delete _feeds[feed];
    }

    function _drop(LibSecp256k1.Point[] memory pubKeys) internal virtual {
        for (uint i; i < pubKeys.length; i++) {
            address feed = pubKeys[i].toAddress();

            if (_feeds[feed].isZeroPoint()) {
                continue;
            }

            emit FeedDropped(msg.sender, feed);
            delete _feeds[feed];
        }
    }

    function _setBar(uint8 bar_) internal virtual {
        require(bar_ != 0);

        emit BarUpdated(msg.sender, bar, bar_);
        bar = bar_;
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
