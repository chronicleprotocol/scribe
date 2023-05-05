Invariants
==========

This document specifies invariants of the Scribe oracle contracts.

Storage: `IScribe.PokeData _pokeData`
-------------------------------------

* Only `poke` function may mutate the struct's state:
    ```
    preTx(_pokeData) != postTx(_pokeData)
        → msg.sig == "poke"
    ```

* `pokeData.age` is strictly monotonically increasing:
    ```
    preTx(_pokeDat.age) != postTx(_pokeData.age)
        → preTx(_pokeData.age) < postTx(_pokeData.age)
    ```

* `pokeData.age` may only be mutated to `block.timestamp`:
    ```
    preTx(_pokeData.age) != postTx(_pokeData.age)
        → postTx(_pokeData.age) == block.timestamp
    ```

* `pokeData.val` can only be read by _toll'ed_ caller.


Storage: `LibSecp256k1.Point[] _pubKeys`
----------------------------------------

* `_pubKeys[0]` is the zero point:
    ```
    _pubKeys[0].isZeroPoint()
    ```

* A non-zero public key exists at most once:
    ```
    ∀x ∊ PublicKeys: x.isZeroPoint() ∨ count(x in _pubKeys) <= 1
    ```

* Length is strictly monotonically increasing:
    ```
    preTx(_pubKeys.length) != postTx(_pubKeys.length)
        → preTx(_pubKeys.length) < posTx(_pubKeys.length)
    ```

* Existing public key may only be deleted, never mutated:
    ```
    ∀x ∊ uint: preTx(_pubKeys[x]) != postTx(_pubKeys[x])
        → postTx(_pubKeys[x].isZeroPoint())
    ```

* Newly added public key is non-zero:
    ```
    preTx(_pubKeys.length) != postTx(_pubKeys.length)
        → postTx(!_pubKeys[_pubKeys.length-1].isZeroPoint())
    ```

* Only functions `lift` and `drop` may mutate the array's state:
    ```
    ∀x ∊ uint: preTx(_pubKeys[x]) != postTx(_pubKeys[x])
        → (msg.sig == "lift" ∨ msg.sig == "drop")
    ```

* Array's state may only be mutated by auth'ed caller:
    ```
    ∀x ∊ uint: preTx(_pubKeys[x]) != postTx(_pubKeys[x])
        → authed(msg.sender)
    ```


Storage: `mapping(address => uint) _feeds`
------------------------------------------

* Image of mapping is `[0, _pubKeys.length)`:
    ```
    ∀x ∊ Address: _feeds[x] ∊ [0, _pubKeys.length)
    ```

* Image of mapping links to feed's public key in `_pubKeys`:
    ```
    ∀x ∊ Address: _feeds[x] = y ⋀ y != 0
        → _pubKeys[y].toAddress() == x
    ```

* Only functions `lift` and `drop` may mutate the mapping's state:
    ```
    ∀x ∊ Address: preTx(_feeds[x]) != postTx(_feeds[x])
        → (msg.sig == "lift" ∨ msg.sig == "drop")
    ```

* Mapping's state may only be mutated by auth'ed caller:
    ```
    ∀x ∊ Address: preTx(_feeds[x]) != postTx(_feeds[x])
        → authed(msg.sender)
    ```
