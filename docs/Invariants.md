# Invariants

This document specifies invariants of the Scribe and ScribeOptimistic oracle contracts.

## `Scribe::_pokeData`

* Only `poke` function may mutate the `_pokeData`:
    ```
    preTx(_pokeData) != postTx(_pokeData)
        → msg.sig == "poke"
    ```

* `_pokeData.age` may only be mutated to `block.timestamp`:
    ```
    preTx(_pokeData.age) != postTx(_pokeData.age)
        → postTx(_pokeData.age) == block.timestamp
    ```

## `ScribeOptimistic::_pokeData`

* Only `poke`, `opPoke`, `opChallenge` and `_afterAuthedAction` protected auth'ed functions may mutate `_pokeData`:
    ```
    preTx(_pokeData) != postTx(_pokeData)
        → msg.sig ∊ {"poke", "opPoke", "opChallenge", "setBar", "drop", "setOpChallengePeriod"}
    ```

* `poke` function may only mutate `_pokeData.age` to `block.timestamp`:
    ```
    preTx(_pokeData) != postTx(_pokeData) ⋀ msg.sig == "poke"
        → postTx(_pokeData.age) == block.timestamp
    ```

* `opPoke`, `opChallenge` and `_afterAuthedAction` protected auth'ed functions may only mutate `_pokeData` to a finalized, non-stale `_opPokeData`:
    ```
    preTx(_pokeData) != postTx(_pokeData) ⋀ msg.sig ∊ {"opPoke", "opChallenge", "setBar", "drop", "setOpChallengePeriod"}
        → postTx(_pokeData) = preTx(_opPokeData) ⋀ preTx(readWithAge()) = preTx(_opPokeData)
    ```

## `{Scribe, ScribeOptimistic}::_pokeData`

* `_pokeData.age` is strictly monotonically increasing:
    ```
    preTx(_pokeData.age) != postTx(_pokeData.age)
        → preTx(_pokeData.age) < postTx(_pokeData.age)
    ```

* `_pokeData.val` can only be read by _toll'ed_ caller.

## `ScribeOptimistic::_opPokeData`

* Only `opPoke`, `opChallenge` and `_afterAuthedAction` protected auth'ed functions may mutate `_opPokeData`:
    ```
    preTx(_opPokeData) != postTx(_opPokeData)
        → msg.sig ∊ {"opPoke", "opChallenge", "setBar", "drop", "setOpChallengePeriod"}
    ```

* `opPoke` function may only set `_opPokeData.age` to `block.timestamp`:
    ```
    preTx(_opPokeData.age) != postTx(_opPokeData.age) ⋀ msg.sig == "opPoke"
        → postTx(_opPokeData.age) == block.timestamp
    ```

* `opChallenge` and `_afterAuthedAction` protected auth'ed functions may only delete `_opPokeData`:
    ```
    preTx(_opPokeData.age) != postTx(_opPokeData.age) ⋀ msg.sig ∊ {"opChallenge", "setBar", "drop", "setOpChallengePeriod"}
        → postTx(_opPokeData.val) == 0 ⋀ postTx(_opPokeData.age) == 0
    ```

## `{Scribe, ScribeOptimistic}::_pubKeys`

* `_pubKeys`' length is 256:
    ```
    _pubKeys.length == 256
    ```

* Public keys are stored at the index of their address' first byte:
    ```
    ∀id ∊ Uint8: _pubKeys[id].isZeroPoint() ∨ (_pubKeys[id].toAddress() >> 152) == id
    ```

* Only functions `lift` and `drop` may mutate the array's state:
    ```
    ∀id ∊ Uint8: preTx(_pubKeys[id]) != postTx(_pubKeys[id])
        → msg.sig ∊ {"lift", "drop"}
    ```

* Array's state may only be mutated by auth'ed caller:
    ```
    ∀id ∊ Uint8: preTx(_pubKeys[id]) != postTx(_pubKeys[id])
        → authed(msg.sender)
    ```
