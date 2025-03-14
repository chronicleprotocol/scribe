// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {Toll} from "chronicle-std/toll/Toll.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";

import {IChronicle} from "chronicle-std/IChronicle.sol";

import {IScribe} from "../IScribe.sol";
import {Scribe} from "../Scribe.sol";

import {IHScribe} from "./IHScribe.sol";

/**
 * @title HScribe
 *
 * @notice Efficient Schnorr multi-signature based Oracle with bounded access to
 *         historical data
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract HScribe is IHScribe, Scribe {
    /// @dev The size of the history ring buffer.
    uint8 internal immutable _size;

    /// @dev The ring buffer storing the last `_size` historical oracle values.
    ///
    /// @dev Note that the ring buffer is fully allocated during construction.
    ///
    /// @custom:invariant Only mutated during poke.
    ///                     preTx(_history) != postTx(_history)
    ///                         → msg.sig == "poke"
    IScribe.PokeData[] internal _history;

    /// @dev The history pointer pointing to the index in `_history` to write
    ///      next to.
    ///
    /// @custom:invariant Only mutated during poke.
    ///                     preTx(_ptr) != postTx(_ptr)
    ///                         → msg.sig == "poke"
    /// @custom:invariant Only incremented in modular arithmetic over `_size`.
    ///                     preTx(_ptr) != postTx(_ptr)
    ///                         → postTx(_ptr) == preTx(_ptr) + 1 (mod _size)
    uint8 internal _ptr;

    constructor(address initialAuthed, bytes32 wat_, uint8 historySize_)
        payable
        Scribe(initialAuthed, wat_)
    {
        require(historySize_ != 0);
        _size = historySize_;

        // Set _history's size.
        assembly ("memory-safe") {
            let slot := _history.slot
            sstore(slot, historySize_)
        }
    }

    /// @inheritdoc IHScribe
    function historySize() external view returns (uint8) {
        return _size;
    }

    //--------------------------------------------------------------------------
    // Overridden Scribe Functions
    //
    // Scribe's poke function is overridden to move the current value from
    // scribe's storage into the history before processing the new poke.
    //
    // Note that no other scribe functionality is modified.

    function _poke(
        IScribe.PokeData calldata pokeData,
        IScribe.SchnorrData calldata schnorrData
    ) internal override(Scribe) {
        // Move current pokeData to history and increment ptr.
        _history[_ptr] = _pokeData;
        _ptr = uint8(addmod(_ptr, 1, _size));

        // Verify poke and update _pokeData.
        super._poke(pokeData, schnorrData);
    }

    //--------------------------------------------------------------------------
    // Historical Read Functions
    //
    // The read functions for historical data are name separated via the `h`
    // prefix to prevent future name clashes.
    //
    // The `hTry` functions only revert if the `past` argument is out of bounds,
    // which can be prevented by the caller via ensuring `past <= historySize()`.
    //
    // Note that passing `past = 0` to any `h`-read function is identical to
    // calling the respective IChronicle's read function, ie:
    //
    //     hRead(0)           == read()
    //   ∧ hTryRead(0)        == tryRead()
    //   ∧ hReadWithAge(0)    == readWithAge()
    //   ∧ hTryReadWithAge(0) == tryReadWithAge()

    /// @inheritdoc IHScribe
    /// @dev Only callable by toll'ed address.
    function hRead(uint8 past) external view toll returns (uint) {
        bool ok;
        uint val;
        (ok, val, /* uint age */ ) = _hTryReadWithAge(past);
        require(ok);

        return val;
    }

    /// @inheritdoc IHScribe
    /// @dev Only callable by toll'ed address.
    function hTryRead(uint8 past) external view toll returns (bool, uint) {
        bool ok;
        uint val;
        (ok, val, /* uint age */ ) = _hTryReadWithAge(past);

        return (ok, val);
    }

    /// @inheritdoc IHScribe
    /// @dev Only callable by toll'ed address.
    function hReadWithAge(uint8 past) external view toll returns (uint, uint) {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = _hTryReadWithAge(past);
        require(ok);

        return (val, age);
    }

    /// @inheritdoc IHScribe
    /// @dev Only callable by toll'ed address.
    function hTryReadWithAge(uint8 past) external view toll returns (bool, uint, uint) {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = _hTryReadWithAge(past);

        return (ok, val, age);
    }

    /// @custom:invariant Reverts iff `past > historySize()`.
    function _hTryReadWithAge(uint8 past) internal view returns (bool, uint, uint) {
        require(past <= _size);

        uint val;
        uint age;
        if (past == 0) {
            val = _pokeData.val;
            age = _pokeData.age;
        } else {
            uint index;
            // Compute index = _ptr - past           (mod _size)
            //               = _ptr + (_size - past) (mod _size)
            //
            // Unchecked because the only protected operation performed is
            // _size - past where past is guaranteed to be less than or equal to
            // _size.
            unchecked {
                index = addmod(_ptr, _size - past, _size);
            }

            IScribe.PokeData memory pokeData = _history[index];
            val = pokeData.val;
            age = pokeData.age;
            // assert(age == 0 || age < _pokeData.age);
        }

        return val != 0 ? (true, val, age) : (false, 0, 0);
    }
}

contract ChronicleHistorical_BASE_QUOTE_COUNTER is HScribe {
    // @todo                 ^^^^ ^^^^^ ^^^^^^^ Adjust name of HScribe instance.
    constructor(address initialAuthed, bytes32 wat_, uint8 historySize_)
        HScribe(initialAuthed, wat_, historySize_)
    {}
}
