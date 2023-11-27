# Benchmarks

The benchmark for `Scribe` is based on the `poke()` function while the benchmark for `ScribeOptimistic` being based on the `opPoke()` function.

| `bar` | `Scribe::poke()` | `ScribeOptimistic::opPoke()` |
| ----- | ---------------- | ---------------------------- |
| 5     | 81,025           | 68,944                       |
| 10    | 106,395          | 69,004                       |
| 15    | 134,342          | 69,061                       |
| 20    | 159,488          | 69,133                       |
| 50    | 320,473          | 69,908                       |
| 100   | 585,993          | 71,315                       |
| 200   | 1,119,535        | 73,759                       |
| 255   | 1,411,702        | 74,852                       |

The following visualization shows the gas usage for different numbers of `bar`:

![](../assets/benchmarks.png)

For more info, see the `script/benchmarks/` directory.
