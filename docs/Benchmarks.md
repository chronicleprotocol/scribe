# Benchmarks

The benchmark for `Scribe` is based on the `poke()` function while the benchmark for `ScribeOptimistic` being based on the `opPoke()` function.

| `bar` | `Scribe::poke()`   | `ScribeOptimistic::opPoke()` |
|-------|--------------------|------------------------------|
|     5 |             79,428 |                       66,462 |
|    10 |            106,862 |                       66,534 |
|    15 |            131,834 |                       66,603 |
|    20 |            158,263 |                       66,663 |
|    50 |            315,655 |                       67,437 |
|   100 |            577,919 |                       68,845 |

The following visualization shows the gas usage for different numbers of `bar`:

![](../assets/benchmarks.png)

For more info, see the `script/benchmarks/` directory.
