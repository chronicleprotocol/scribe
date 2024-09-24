# Management

This document describes how to manage deployed `Scribe` and `ScribeOptimistic` instances.

## Table of Contents

- [Management](#management)
  - [Table of Contents](#table-of-contents)
  - [Environment Variables](#environment-variables)
  - [Functions](#functions)
    - [`IScribe::setBar`](#iscribesetbar)
    - [`IScribe::lift`](#iscribelift)
    - [`IScribe::lift multiple`](#iscribelift-multiple)
    - [`IScribe::drop`](#iscribedrop)
    - [`IScribe::drop multiple`](#iscribedrop-multiple)
    - [`IScribeOptimistic::setOpChallengePeriod`](#iscribeoptimisticsetopchallengeperiod)
    - [`IScribeOptimistic::setMaxChallengeReward`](#iscribeoptimisticsetmaxchallengereward)
    - [`IAuth::rely`](#iauthrely)
    - [`IAuth::deny`](#iauthdeny)
    - [`IToll::kiss`](#itollkiss)
    - [`IToll::diss`](#itolldiss)
  - [Offboarding](#offboarding)
    - [Deactivation](#deactivation)
    - [Fund Rescue](#fund-resuce)
    - [Killing](#killing)

## Environment Variables

The following environment variables must be set for all commands:

- `RPC_URL`: The RPC URL of an EVM node
- `KEYSTORE`: The path to the keystore file containing the encrypted private key
- `KEYSTORE_PASSWORD`: The password of the keystore file
- `SCRIBE`: The `Scribe`/`ScribeOptimistic` instance to manage
- `SCRIBE_FLAVOUR`: The `Scribe` flavour to manage
    - Note that value must be either `Scribe` or `ScribeOptimistic`

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variable's values', and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "KEYSTORE" -e "KEYSTORE_PASSWORD" -e "SCRIBE" -e "SCRIBE_FLAVOUR"
```

## Functions

### `IScribe::setBar`

Set the following environment variables:

- `BAR`: The bar to set

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "setBar(address,uint8)" "$SCRIBE" "$BAR") \
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
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "lift(address,uint,uint,uint8,bytes32,bytes32)" "$SCRIBE" "$PUBLIC_KEY_X_COORDINATE" "$PUBLIC_KEY_Y_COORDINATE" "$ECDSA_V" "$ECDSA_R" "$ECDSA_S") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IScribe::lift multiple`

Set the following environment variables:

- `PUBLIC_KEY_X_COORDINATES`: The feeds' public keys' `x` coordinates
- `PUBLIC_KEY_Y_COORDINATES`: The feeds' public keys' `y` coordinates
- `ECDSA_VS`: The feeds' `feedRegistrationMessage` ECDSA signatures' `v` fields
- `ECDSA_RS`: The feeds' `feedRegistrationMessage` ECDSA signatures' `r` fields
    - Note that the values must be provided as `bytes32`
- `ECDSA_SS`: The feeds' `feedRegistrationMessage` ECDSA signatures' `s` fields
    - Note that the values must be provided as `bytes32`

Note to use the following format for lists: `"[<elem>,<elem>]"`

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "lift(address,uint[],uint[],uint8[],bytes32[],bytes32[])" "$SCRIBE" "$PUBLIC_KEY_X_COORDINATES" "$PUBLIC_KEY_Y_COORDINATES" "$ECDSA_VS" "$ECDSA_RS" "$ECDSA_SS") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IScribe::drop`

Set the following environment variables:

- `FEED_ID`: The feed's id

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "drop(address,uint8)" "$SCRIBE" "$FEED_ID") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IScribe::drop multiple`

Set the following environment variables:

- `FEED_IDS`: The feeds' ids

Note to use the following format for lists: `"[<elem>,<elem>]"`

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "drop(address,uint8[])" "$SCRIBE" "$FEED_IDS") \
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
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "setOpChallengePeriod(address,uint16)" "$SCRIBE" "$OP_CHALLENGE_PERIOD") \
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
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "setMaxChallengeReward(address,uint)" "$SCRIBE" "$MAX_CHALLENGE_REWARD") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```


### `IAuth::rely`

Set the following environment variables:

- `WHO`: The address to grant auth to

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "rely(address,address)" "$SCRIBE" "$WHO") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IAuth::deny`

Set the following environment variables:

- `WHO`: The address to renounce auth from

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "deny(address,address)" "$SCRIBE" "$WHO") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IToll::kiss`

Set the following environment variables:

- `WHO`: The address to grant toll to

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "kiss(address,address)" "$SCRIBE" "$WHO") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### `IToll::diss`

Set the following environment variables:

- `WHO`: The address to renounce toll from

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "diss(address,address)" "$SCRIBE" "$WHO") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

## Offboarding

Offboarding a Scribe(Optimistic) instance simply means _Chronicle Protocol_ is not guaranteeing pokes anymore, ie the oracle is not being updated anymore.

However, to ensure an offboarded Scribe(Optimistic) instance may not behave unexpectedly it needs to be deactivated. Furthermore, if the contract is a ScribeOptimistic instance ETH held by the contract may need to be rescued. If its certain the contract will never be used again it is recommended to kill it.

### Deactivation

Deactivating a Scribe(Optimistic) instance means its value is set to zero, leading all `read()` calls to revert/fail, no feeds are lifted, and `bar` is set to `255`.

Note that one or more addresses still hold `auth` on the contract meaning the instance can be reactivated via `lift`-ing feeds and updating `bar` again.

> [!IMPORTANT]
>
> Deactivation requires running two distinct `forge script` commands.
>
> It is of utmost importance to run both commands and NOT leave the Scribe(Optimistic) instance in an undefined state.

Step 1:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "deactivate_Step1(address)" "$SCRIBE") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

Step 2:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "deactivate_Step2(address)" "$SCRIBE") \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```

### Fund Rescue

TODO: Rescuing funds

### Killing

Killing a deactivated Scribe(Optimistic) instance ensures it cannot be activated again. Note that killing an instance makes the contract's state immutable via `deny`-ing `auth` for every address.

Run:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig $(cast calldata "kill(address)" "$SCRIBE") \
    --sender $(cast wallet address --keystore $KEYSTORE --password $KEYSTORE_PASSWORD) \
    -vvv \
    script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script
```
