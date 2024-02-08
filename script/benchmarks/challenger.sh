#!/bin/bash

# Script to run challenger benchmarks.
#
# Run via:
# ```bash
# $ script/benchmarks/challenger.sh
# ```

poke () {
    forge script script/benchmarks/ScribeBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "poke()" > /dev/null 2>&1
    sleep 1
}

run () {
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

    # Note to poke couple of times to have non-zero storage slots.
    poke
    poke

    # Make invalid opPoke, challenge it, and grep the gas usage.
    cost=$(forge script script/benchmarks/ScribeOptimisticBenchmark.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sig "opPokeInvalidAndChallenge()" 2>/dev/null | grep -oE "[0-9]+ gas")

    # Kill anvil
    kill $anvilPID

    # Print cost of challenge tx.
    # Note that $cost contains 3 gas numbers, opPoke cost, opChallenge cost,
    # and total cost, eg `2000 gas 3000 gas 5000 gas`.
    # Therefore, only select the middle gas value.
    echo $cost | awk '{print $3, " ", $4}'
    echo ""
}

echo "=== Challenger Benchmarks (Printing cost of opChallenge())"
run 5
run 10
run 15
run 20
run 50
run 100
run 200
run 255
