#!/bin/bash

# Script to print the storage layout of Scribe and ScribeOptimistic
#
# Run via:
# ```bash
# $ script/dev/print-storage-layout.sh
# ```

echo "Scribe Storage Layout"
forge inspect src/Scribe.sol:Scribe storage --pretty

echo ""

echo "ScribeOptimistic Storage Layout"
forge inspect src/ScribeOptimistic.sol:ScribeOptimistic storage --pretty
