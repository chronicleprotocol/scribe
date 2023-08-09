# Management

This document describes how to manage deployed `Scribe` and `ScribeOptimistic` instances.

## Table of Contents

- [Management](#management)
  - [Table of Contents](#table-of-contents)
  - [Environment Variables](#environment-variables)
  - [Functions](#functions)
    - [`IScribe::setBar`](#iscribesetbar)
    - [`IScribe::lift`](#iscribelift)
    - [`IScribe::drop`](#iscribedrop)
    - [`IScribeOptimistic::setOpChallengePeriod`](#iscribeoptimisticsetopchallengeperiod)
    - [`IScribeOptimistic::setMaxChallengeReward`](#iscribeoptimisticsetmaxchallengereward)
    - [`IAuth::rely`](#iauthrely)
    - [`IAuth::deny`](#iauthdeny)
    - [`IToll::kiss`](#itollkiss)
    - [`IToll::diss`](#itolldiss)

## Environment Variables

The following environment variables must be set for all commands:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use
- `SCRIBE`: The `Scribe`/`ScribeOptimistic` instance to manage
- `SCRIBE_FLAVOUR`: The `Scribe` flavour to manage
    - Note that value must be either `Scribe` or `ScribeOptimistic`

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variable's values', and run `source .env`.

## Functions

### `IScribe::setBar`

Set the following environment variables:

- `BAR`: The bar to set

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setBar(address,uint8)" $SCRIBE $BAR) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IScribe::lift`

Set the following environment variables:

- `PUBLIC_KEY_X_COORDINATE`: The feed's public key's `x` coordinate
- `PUBLIC_KEY_Y_COORDINATE`: The feed's public key's `y` coordinate
- `ECDSA_V`: The feed's `feedRegistrationMessage` ECDSA signature's `v` field
- `ECDSA_R`: The feed's `feedRegistrationMessage` ECDSA signature's `r` field
    - Note that the value must be provided as `bytes32`
- `ECDSA_S`: The feed's `feedRegistrationMessage` ECDSA signature's `s` field
    - Note that the value must be provided as `bytes32`

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "lift(address,uint,uint,uint8,bytes32,bytes32)" $SCRIBE $PUBLIC_KEY_X_COORDINATE $PUBLIC_KEY_Y_COORDINATE $ECDSA_V $ECDSA_R $ECDSA_S) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IScribe::drop`

Set the following environment variables:

- `FEED_INDEX`: The feed's index

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "drop(address,uint)" $SCRIBE $FEED_INDEX) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IScribeOptimistic::setOpChallengePeriod`

> **Warning**
>
> This command is only supported if the `Scribe` instance is of type `IScribeOptimistic`!

Set the following environment variables:

- `OP_CHALLENGE_PERIOD`: The length of the optimistic challenge period to set, in seconds

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setOpChallengePeriod(address,uint16)" $SCRIBE $OP_CHALLENGE_PERIOD) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```


### `IScribeOptimistic::setMaxChallengeReward`

> **Warning**
>
> This command is only supported if the `Scribe` instance is of type `IScribeOptimistic`!

Set the following environment variables:

- `MAX_CHALLENGE_REWARD`: The max challenge reward to set

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setMaxChallengeReward(address,uint)" $SCRIBE $MAX_CHALLENGE_REWARD) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```


### `IAuth::rely`

Set the following environment variables:

- `WHO`: The address to grant auth to

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "rely(address,address)" $SCRIBE $WHO) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IAuth::deny`

Set the following environment variables:

- `WHO`: The address renounce auth from

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "deny(address,address)" $SCRIBE $WHO) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IToll::kiss`

Set the following environment variables:

- `WHO`: The address grant toll to

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "kiss(address,address)" $SCRIBE $WHO) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IToll::diss`

Set the following environment variables:

- `WHO`: The address renounce toll from

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "diss(address,address)" $SCRIBE $WHO) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```