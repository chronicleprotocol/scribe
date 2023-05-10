# Scribe

This document provides technical documentation for Chronicle Protocol's Scribe oracle system.


## Background

The Scribe oracle system is the successor of MakerDAO's [`median`](https://github.com/makerdao/median/blob/master/src/median.sol) contract.

The `median` contract provides a public callable `poke()` function receiving a
set of ECDSA signed `(value, age)` tuples. After a successfull `poke()`, the
`median`'s oracle value is the median of the provided values.

Each `(value, age)` tuple's ECDSA signature's signer needs to be recovered and
checked to be a whitelisted feed. This ensures only whitelisted feeds are able
to participate in setting the oracle's value.

Furthermore, the `poke()` function expects exactly `bar` many `(value, age)` tuples.
This ensures only a specified number of feeds together are able to advance the oracle
to a new value.


## Problems with `median`

The `median`'s `poke()` function's gas cost is linear dependent to `bar`.
Furthermore, the `poke()` function needs to execute `bar` many `ecrecover` calls
to verify each tuple's ECDSA signature.

The goal of developing Scribe was to lower the gas costs of the `poke()` function.


## Scribe Overview

In order to reduce the amount of signature verification onchain, Scribe uses
aggregated (or multi) signatures. This reduces the number of onchain signature
verifications from `O(bar)` to `O(1)`. Furthermore, feeds can now already compute
the median offchain, and multisign only the result.
This also reduces the calldata from `O(bar)` to `O(1)` as only a single
`(value, age)` tuple is needed.


### Scribe's Signature Scheme

We benchmarked two different signature algorithms, BLS and Schnorr.

The BLS PoC, using the *alt_bn_128* curve, showed an increase in runtime cost
of more than 200% for a `bar` value of 15. Note that *alt_bn_128*'s usage is
discouraged and the Ethereum community is generally switching to the *BLS12-381*
curve. However, there are no precompiles for that curve yet, see [EIP-2537](https://eips.ethereum.org/EIPS/eip-2537).

Verifying a Schnorr signature on the other side is possible via a single elliptic
curve multiplication. The Schnorr scheme used by Scribe allows using `ecrecover`
to perform the elliptic curve multiplication.

However, the verification is only the last part. Before that the participating
public keys need to be aggregated - onchain. Note that the aggregated keys cannot
just be pushed onchain due to a combinatoric explosion of possible keys, i.e. if
`bar` is 15 and there are 20 whitelisted feeds, the number of possible aggregated
public key combinations is `choose 15 from 20 ~= 15,000`.

For Scribe's Schnorr scheme, the public keys are aggregated by adding the them
together. Therefore, Scribe needs to perform elliptic curve point additions.
For more info about the Schnorr scheme, see [here](./Schnorr.md).


### Scribe's `LibSecp256k1` Library

Scribe uses the secp256k1 elliptic curve. In order to optimize the addition of
public keys, i.e. elliptic curve points, the library uses an addition formula
that allows adding a point in Jacobian coordinates to a point in Affine coordinates.

Note that elliptic curve addition in Jacobian coordinates is a lot cheaper.
However, converting a point from Jacobian coordinates back to Affine coordinates
involves computing a modular inverse, which is very expensive.

Converting Affine coordinates to Jacobian coordinates on the other side is trivial -
just add a `z` variable with value 1. The formula addition expects one of the two points
to a have a `z` coordinate of 1, effectively allowing us to add the next public key's point
in Affine coordinates to the current sum in Jacobian coordinates.

After adding all points together, we once convert from Jacobian back to Affine coordinates.
For more info see [`LibSecp256k1::addAffinePoint()`](../src/libs/LibSecp256k1.sol).


###
