#!/bin/bash

# Script to generate Scribe's and ScribeOptimistic's flattened contracts.
# Saves the contracts in fresh flattened/ directory.
#
# Run via:
# ```bash
# $ script/dev/generate-flattened.sh
# ```

rm -rf flattened/
mkdir flattened

echo "Generating flattened Scribe contract"
forge flatten src/Scribe.sol > flattened/Scribe.sol

echo ""

echo "Generating flattened ScribeOptimistic contract"
forge flatten src/ScribeOptimistic.sol > flattened/ScribeOptimistic.sol
