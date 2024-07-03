# Deployment

This document describes how to deploy `Scribe` and `ScribeOptimistic` instances.

## Environment Variables

The following environment variables must be set:

- `RPC_URL`: The RPC URL of an EVM node
- `KEYSTORE`: The path to the keystore file containing the encrypted private key
    - Note that password can either be entered on request or set via the `KEYSTORE_PASSWORD` environment variable
- `KEYSTORE_PASSWORD`: The password for the keystore file
- `ETHERSCAN_API_URL`: The Etherscan API URL for the Etherscan's chain instance
    - Note that the API endpoint varies per Etherscan chain instance
    - Note to point to actual API endpoint (e.g. `/api`) and not just host
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `SCRIBE_FLAVOUR`: The `Scribe` flavour to deploy
    - Note that value must be either `Scribe` or `ScribeOptimistic`
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Scribe` instance
- `WAT`: The wat for `Scribe`
    - Note to use the wat's string representation
    - Note that the wat must not exceed 32 bytes in length

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variables' values, and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "KEYSTORE" -e "KEYSTORE_PASSWORD" -e "ETHERSCAN_API_URL" -e "ETHERSCAN_API_KEY" -e "SCRIBE_FLAVOUR" -e "INITIAL_AUTHED" -e "WAT"
```

## Code Adjustments

Two code adjustments are necessary to give each deployed contract instance a unique name:

1. Adjust the `Chronicle_BASE_QUOTE_COUNTER`'s name in `src/${SCRIBE_FLAVOUR}.sol` and remove the `@todo` comment
2. Adjust the import of the `Chronicle_BASE_QUOTE_COUNTER` in `script/${SCRIBE_FLAVOUR}.s.sol` and remove the `@todo` comment

## Execution

The deployment process consists of two steps - the actual deployment and the subsequent Etherscan verification.

Deployment:

```bash
$ SALT_BYTES32=$(cast format-bytes32-string $SALT) && \
  WAT_BYTES32=$(cast format-bytes32-string $WAT) && \
  forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig "$(cast calldata "deploy(address,bytes32)" "$INITIAL_AUTHED" "$WAT_BYTES32")" \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

The deployment command will log the address of the newly deployed contract address. Store this address in the `$SCRIBE` environment variable and continue with the verification.

Verification:

```bash
$ WAT_BYTES32=$(cast format-bytes32-string $WAT) && \
  forge verify-contract \
    "$SCRIBE" \
    --verifier-url "$ETHERSCAN_API_URL" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes32)" "$INITIAL_AUTHED" "$WAT_BYTES32") \
    src/${SCRIBE_FLAVOUR}.sol:${SCRIBE_FLAVOUR}_1
```
