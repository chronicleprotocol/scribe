#!/bin/bash

# Script to (invalid) opPoke a ScribeOptimistic instance.
# Useful to test opChallenger implementations.
#
# Requirements:
# - Expects ScribeOptimistic instance to be deploed at `SCRIBE`
# - Expects an `opChallengePeriod` of at most 10 minutes
#
# Run via:
# ```bash
# $ script dev/invalid-oppoker.sh
# ```

# @todo Set constants
PRIVATE_KEY=
RPC_URL=
SCRIBE=
# Feed private keys taken from script/dev/test-feeds.json.
FEED_PRIVATE_KEYS='[2,3,4,5,6,7,8,9,10,11,12,14,15,16,17,18,19,20,21,22]'

while true; do
    # Lift feeds
    # Note that feeds must be lifted after each opPoke call to ensure a possibly
    # kicked feed, due to signing an invalid opPoke and being challenged, is
    # lifted again
    forge script \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        --rpc-url "$RPC_URL" \
        --sig $(cast calldata "lift(address,uint[])" "$SCRIBE" "$FEED_PRIVATE_KEYS") \
        script/dev/ScribeTester.s.sol:ScribeTesterScript

    # Generate a random number between 1 and 100
    random_number=$((RANDOM % 100 + 1))

    if [ "$random_number" -le 50 ]; then
        # If number is <= 50 (ie 50% chance), make invalid opPoke.
        forge script \
           --private-key "$PRIVATE_KEY" \
           --broadcast \
           --rpc-url "$RPC_URL" \
           --sig $(cast calldata "opPoke_invalid(address,uint[],uint128)" "$SCRIBE" "$FEED_PRIVATE_KEYS" "$random_number") \
           script/dev/ScribeOptimisticTester.s.sol:ScribeOptimisticTesterScript

        echo "Pushed invalid opPoke"
    else
        # Otherwise make valid opPoke.
        forge script \
           --private-key "$PRIVATE_KEY" \
           --broadcast \
           --rpc-url "$RPC_URL" \
           --sig $(cast calldata "opPoke(address,uint[],uint128)" "$SCRIBE" "$FEED_PRIVATE_KEYS" "$random_number") \
           script/dev/ScribeOptimisticTester.s.sol:ScribeOptimisticTesterScript

        echo "Pushed valid opPoke"
    fi

    # Sleep for 10 minutes
    sleep 600
done
