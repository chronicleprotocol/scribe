#!/bin/bash

# Script to run Scribe and ScribeOptimistic benchmarks.
#
# Run via:
# ```bash
# $ script/benchmarks/run.sh
# ```

poke () {
    forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()" > /dev/null 2>&1
    sleep 1
}

run_Scribe () {
    local bar=$1
    echo "Benchmarking bar=$bar"
    # Start anvil in background
    anvil -b 1 > /dev/null &
    anvilPID=$!

    # Deploy Scribe
    forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "deploy()" > /dev/null 2>&1
    # Set bar
    forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig $(cast calldata "setBar(uint8)" $bar) > /dev/null 2>&1
    # Lift feeds
    forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()" > /dev/null 2>&1
    # Poke once
    poke

    # Poke again and grep gas usage
    cost=$(forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()" 2>/dev/null | grep -oE "[0-9]+ gas")

    # Kill anvil
    kill $anvilPID

    # Print cost of non-initial poke
    echo $cost | awk '{print $1, " ", $2}'
    echo ""
}

run_ScribeOptimistic () {
    local bar=$1
    echo "Benchmarking bar=$bar"
    # Start anvil in background
    anvil -b 1 > /dev/null &
    anvilPID=$!

    # Deploy ScribeOptimistic
    forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "deploy()" > /dev/null 2>&1
    # Set bar
    forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig $(cast calldata "setBar(uint8)" $bar) > /dev/null 2>&1
    # Lift feeds
    forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "liftFeeds()" > /dev/null 2>&1
    # Set opChallengePeriod
    forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "setOpChallengePeriod()" > /dev/null 2>&1
    # Poke once
    poke
    # Poke again
    poke

    # opPoke and grep gas usage
    cost=$(forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "opPoke()" 2>/dev/null | grep -oE "[0-9]+ gas")

    # Kill anvil
    kill $anvilPID

    # Print cost of non-initial opPoke
    echo $cost | awk '{print $1, " ", $2}'
    echo ""
}


echo "=== Scribe Benchmarks (Printing cost of non-initial poke())"
run_Scribe 5
run_Scribe 10
run_Scribe 15
run_Scribe 20
run_Scribe 50
run_Scribe 100
run_Scribe 200
run_Scribe 255

echo "=== Scribe Optimistic Benchmarks (Printing cost of non-initial opPoke())"
run_ScribeOptimistic 5
run_ScribeOptimistic 10
run_ScribeOptimistic 15
run_ScribeOptimistic 20
run_ScribeOptimistic 50
run_ScribeOptimistic 100
run_ScribeOptimistic 200
run_ScribeOptimistic 255
