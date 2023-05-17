# Scribe

This document provides technical documentation for Chronicle Protocol's Scribe oracle system.


## Table of Contents

- [Scribe](#scribe)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Schnorr Signature Scheme](#schnorr-signature-scheme)
  - [Elliptic Curve Computations](#elliptic-curve-computations)
  - [Encoding of Participating Public Keys](#encoding-participating-public-keys)
  - [Lifting Feeds](#lifting-feeds)
  - [Chainlink Compatibility](#chainlink-compatibility)
  - [Optimistic-Flavored Scribe](#optimistic-flavored-scribe)
    - [Verifying Optimistic Pokes](#verifying-optimistic-pokes)
  - [Benchmarks](#benchmarks)

## Overview

Scribe is an efficient Schnorr multi-signature based oracle allowing a subset of feeds to multi-sign a `(value, age)` tuple via a custom Schnorr scheme. The oracle advances to a new `(value, age)` tuple - via the public callable `poke()` function - if the given tuple is signed by exactly `IScribe::bar()` many feeds.

The Scribe contract also allows the creation of an _optimistic-flavored_ oracle instance with onchain fault resolution called _ScribeOptimistic_.

Scribe implements Chronicle Protocol's [`IChronicle`](https://github.com/chronicleprotocol/chronicle-std/blob/v1/src/IChronicle.sol) interface for reading the oracle's value.

To protect authorized functions, Scribe uses `chronicle-std`'s [`Auth`](https://github.com/chronicleprotocol/chronicle-std/blob/v1/src/auth/Auth.sol) module. Functions to read the oracle's value are protected via `chronicle-std`'s [`Toll`](https://github.com/chronicleprotocol/chronicle-std/blob/v1/src/toll/Toll.sol) module.


## Schnorr Signature Scheme

Scribe uses a custom Schnorr signature scheme. The scheme is specified in [docs/Schnorr.md](./Schnorr.md).

The verification logic is implemented in [`LibSchnorr.sol`](../src/libs/LibSchnorr.sol). A Solidity library to (multi-) sign data is provided via [`script/libs/LibSchnorrExtended.sol`](../script/libs/LibSchnorrExtended.sol).


## Elliptic Curve Computations

Scribe needs to perform elliptic curve computations on the secp256k1 curve to verify aggregated/multi signatures.

The [`LibSecp256k1.sol`](../src/libs/LibSecp256k1.sol) library provides the necessary addition and point conversion (Affine coordinates <-> Jacobian coordinates) functions.

In order to save computation-heavy conversions from Jacobian coordinates - which are used for point addition - back to Affine coordinates - which are used to store public keys -, `LibSecp256k1` uses an addition formula expecting one point's `z` coordinate to be 1. Effectively allowing to add a point in Affine coordinates to a point in Jacobian coordinates.

This optimization allows Scribe to aggregate public keys, i.e. compute the sum of secp256k1 points, in an efficient manner by only having to convert the end result from Jacobian coordinates to Affine coordinates.

For more info, see [`LibSecp256k1::addAffinePoint()`](../src/libs/LibSecp256k1.sol).


## Encoding Participating Public Keys

The `poke()` function has to receive the set of feeds, i.e. public keys, that participated in the Schnorr multi-signature.

To reduce the calldata load, Scribe does not use type `address`, which uses 20 bytes per feed, but encodes the unique feeds' identifier's byte-wise into a `bytes` type called `signersBlob`.

For more info, see [`LibSchnorrData.sol`](../src/libs/LibSchnorrData.sol).


## Lifting Feeds

Feeds _must_ prove the integrity of their public key by proving the ownership of the corresponding private key. The `lift()` function therefore expects an ECDSA signed message derived from `IScribe::wat()`.

If public key's would not be verified, the Schnorr signature verification would be vulnerable to rogue-key attacks. For more info, see [`docs/Schnorr.md`](./Schnorr.md#key-aggregation-for-multisignatures).

Also, the number of state-changing `lift()` executions is limited to `type(uint8).max-1`, i.e. 254. After reaching this limit, no further `lift()` calls can be executed. For more info, see [`IScribe.maxFeeds()`](../src/IScribe.sol).


## Chainlink Compatibility

Scribe aims to be partially Chainlink compatible by implementing the most widely, and not deprecated, used functions of the `IChainlinkAggregatorV3` interface.

The following `IChainlinkAggregatorV3` functions are provided:
- `latestRoundData()`
- `decimals()`


## Optimistic-Flavored Scribe

_ScribeOptimistic_ is a contract inheriting from Scribe and providing an _optimistic-flavored_ Scribe version. This version is intended to only be used on Layer 1s with expensive computation.

To circumvent verifying Schnorr signatures onchain, `ScribeOptimistic` provides an additional `opPoke()` function. This function expects the `(value, age)` tuple and corresponding Schnorr signature to be signed via ECDSA by a single feed.

The `opPoke()` function binds the feed to the data they signed. A public callable `opChallenge()` function can be called at any time. The function verifies the current optimistically poked data and, if the Schnorr signature verification succeeds, finalizes the data. However, if the Schnorr signature verification fails, the feed bound to the data is automatically `diss`'ed, i.e. removed from the whitelist, and the data deleted.

If an `opPoke()` is not challenged, its value finalized after a specified period. For more info, see [`IScribeOptimistic::opChallengePeriod()](../src/IScribeOptimistic.sol).

Monitoring optimistic pokes and, if necessary, challenging them can be incentivized via ETH rewards. For more info, see [`IScribeOptimistic::maxChallengeReward()`](../src/IScribeOptimistic.sol).


### About Bounded Gas Usage

For all functions being executed during `opChallenge()`, it is of utmost importance to have bounded gas usage. These functions are marked with `@custom:invariant` specifications documenting their gas usage.

The gas usage _must_ be bounded to ensure an invalid `opPoke()` can always be successfully challenged.

Two loops are executed during an `opChallenge()`:
1. Inside `Scribe::_verifySchnorrSignature` - bounded by `bar`
2. Inside `LibSecp256k1::_invMod` - computing the modular inverse of a Jacobian `z` coordinate of a secp256k1 point


### Verifying Optimistic Pokes

1. Listen to `opPoked` events:
```solidity
event OpPoked(
       address indexed caller,
       address indexed opFeed,
       IScribe.SchnorrData schnorrData,
       IScribe.PokeData pokeData
);
```

2. Construct message from `pokeData`:
```solidity
function constructPokeMessage(PokeData calldata pokeData)
       external
       view
       returns (bytes32);
```

3. Verify Schnorr signature:
```solidity
function verifySchnorrSignature(
        bytes32 message,
        SchnorrData calldata schnorrData
) external returns (bool ok, bytes memory err);
```

4. If signature verifications fails:
```solidity
function opChallenge(SchnorrData calldata schnorrData)
        external
        returns (bool);
```

5. ETH Challenge reward can be checked beforehand:
```solidity
function challengeReward() external view returns (uint);
```

## Benchmarks

Benchmarks can be found in [`script/benchmarks/`](../script/benchmarks/).
