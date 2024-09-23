#!/bin/bash

# Tool to generate new encryped keystore with Ethereum address matching
# a specific first byte identifier.
#
# Dependencies:
# - cast, see https://getfoundry.sh
# - unix utilities
#
# Usage:
# ./wallet-generator.sh <0x prefixed byte> <keystore password> <keystore path>
#
# Example:
# ./wallet-generator.sh 0xff test ./keystores

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <0x prefixed byte> <keystore password> <keystore path>"
  exit 1
fi

assigned_id="$1"
password="$2"
path="$3"

if [ -z "$assigned_id" ] || [ -z "$password" ] || [ -z "$path" ]; then
  echo "Usage: $0 <0x prefixed byte> <keystore password> <keystore path>"
  exit 1
fi

# Note to ensure assigned_id is in lower case.
assigned_id=$(echo "$assigned_id" | tr '[:upper:]' '[:lower:]')

ctr=0
while true; do
    # Create new keystore and catch output.
    output=$(cast wallet new --unsafe-password "$password" "$path")

    # Get path and address of new keystore from output.
    keystore=$(echo "$output" | awk '/Created new encrypted keystore file:/ {print $6}')
    address=$(echo "$output" | awk '/Address:/ {print $2}')

    # Get address' id in lower case.
    id=$(echo "${address:0:4}" | tr '[:upper:]' '[:lower:]')

    # Check whether first byte matches assigned id.
    if [ "$id" == "$assigned_id" ]; then
        # Found fitting address. Print output and exit.
        echo "Generated new validator address with id=$id. Needed $ctr tries."
        echo "Keystore: $keystore"
        echo "Address: $address"

        exit 0
    else
        # If address does not fit, delete keystore again.
        rm "$keystore"
    fi

    ctr=$((ctr + 1))
done
