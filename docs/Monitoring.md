# Monitoring

This document describes how `Scribe` and `ScribeOptimistic` instances can be monitored.

## Table of Contents

- [Monitoring](#monitoring)
    - [Table of Contents](#table-of-contents)
    - [Environment Variables](#environment-variables)
    - [Functions](#functions)
        - [`IScribe::readWithAge`](#iscribereadwithage)

## Environment Variables

The following environment variables must be set for all commands:

- `RPC_URL`: The RPC URL of an EVM node
- `SCRIBE`: The `Scribe`/`ScribeOptimistic` instance to monitor
- `SCRIBE_FLAVOUR`: The `Scribe` flavour to monitor
    - Note that value must be either `Scribe` or `ScribeOptimistic`

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variable's values', and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "SCRIBE" -e "SCRIBE_FLAVOUR"
```

## Functions

### `IScribe::readWithAge`

Run:

```bash
$ forge script \
    --sig $(cast calldata "readWithAge(address)" $SCRIBE) \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

Example Output:

```
== Logs ==
  price=1610.105000000000000000, age=1694409384
```
