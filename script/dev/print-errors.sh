#!/bin/bash
#
# Script to print all error identifiers.
#
# Run via:
# ```bash
# $ script/dev/print-errors.sh
# ```

echo "Scribe(Optimistic) Errors"
forge inspect src/ScribeOptimistic.sol:ScribeOptimistic errors
