# Deployment

This document describes how to deploy `Scribe` and `ScribeOptimistic` instance via _Chronicle Protocol_'s [`Greenhouse`](https://github.com/chronicleprotocol/greenhouse) contract factory.

## Environment Variables

The following environment variables must be set:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `GREENHOUSE`: The `Greenhouse` instance to use for deployment
- `SCRIBE_FLAVOUR`: The `Scribe` flavour to deploy
    - Note that value must be either `Scribe` or `ScribeOptimistic`
- `SALT`: The salt to deploy the `Scribe` instance to
    - Note to use the salt's string representation
    - Note that the salt must not exceed 32 bytes in length
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Scribe` instance
- `WAT`: The wat for `Scribe`
    - Note to use the wat's string representation
    - Note that the wat must not exceed 32 bytes in length

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variable's values', and run `source .env`.

## Code Adjustments

In order to have the `wat` in the name of the deployed instance, the code inside `Scribe.s.sol` or `ScribeOptimistic.s.sol` - depending on which `Scribe` flavour to deploy - must be adjusted.

1. Adjust the name of the `Chronicle_BASE_QUOTE_COUNTER` contract
2. Adjust the name of the contract inside the `deploy` function
3. Remove both `@todo` comments

## Execution

Run:

```bash
$ SALT_BYTES32=$(cast format-bytes32-string $SALT) && \
  WAT_BYTES32=$(cast format-bytes32-string $WAT) && \
  forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verify \
    --sig $(cast calldata "deploy(address,bytes32,address,bytes32)" $GREENHOUSE $SALT_BYTES32 $INITIAL_AUTHED $WAT_BYTES32) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```
