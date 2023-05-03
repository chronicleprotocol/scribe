#!/bin/bash

# Script to generate Scribe's and ScribeOptimistic's ABIs.
# Saves the ABIs in fresh abis/ directory.
#
# Run via:
# ```bash
# $ script/dev/generate-abis.sh
# ```

rm -rf abis/
mkdir abis

echo "Generating Scribe's ABI"
forge inspect src/Scribe.sol:Scribe abi > abis/Scribe.json

echo ""

echo "Generating ScribeOptimistic's ABI"
forge inspect src/ScribeOptimistic.sol:ScribeOptimistic abi > abis/ScribeOptimistic.json
