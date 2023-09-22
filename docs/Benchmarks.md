# Benchmarks

The benchmark for `Scribe` is based on the `poke()` function while the benchmark for `ScribeOptimistic` being based on the `opPoke()` function.

| `bar` | `Scribe::poke()` | `ScribeOptimistic::opPoke()` |
| ----- | ---------------- | ---------------------------- |
| 5     | 80,280           | 68,815                       |
| 10    | 105,070          | 68,887                       |
| 15    | 132,414          | 68,944                       |
| 20    | 156,983          | 69,004                       |
| 50    | 314,455          | 69,791                       |
| 100   | 574,227          | 71,186                       |
| 200   | 1,096,599        | 73,630                       |
| 255   | 1,382,810        | 74,735                       |

The following visualization shows the gas usage for different numbers of `bar`:

![](../assets/benchmarks.png)

For more info, see the `script/benchmarks/` directory.
