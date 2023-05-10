# [WIP] General Docs

## About bounded gas usage

For many functions it is of utmost importance to have bounded gas usage.
These functions are marked with `@custom:invariant` specifications.

This requirement is because `opChallenge` MUST be able to succeed if an `opPoke`
is invalid.

There are two loops being executed during `opChallenge`:
1. Inside `Scribe::_verifySchnorrSignature` - bounded by `bar`
2. Inside `LibSecp256k1::_invMod` - computing the modular inverse for a Jacobian
   `z` coordinate of a secp256k1 point

@audit Need mathematical guarantee that invMod's loop is bounded!
@audit-info Have guarantee that `z` coordinate belongs to point on curve due to
            each point's private key being verified via ECDSA.


## About `LibSecp256k1`

- Affine coordinates are the "normal" ones, e.g. the Ethereum address is defined
  via this representation
- But addition is a lot cheaper in Jacobian coordinates
- `LibSecp256k1`'s addition formula expects the one point's `z` coordinate to
  be 1
- Luckily, converting from Affine to Jacobian coordinates is trivially - adding
  a `z` coordinate with value 1
- Converting from Jacobian to Affine involves computing `z`'s inverse
    - Computing an inverse is very expensive!
- Therefore, aggregate public keys (perform point additions) in Jacobian
  coordinates and convert back to Affine coordinates only at the end


## About `SchnorrData.signersBlob`

The `SchnorrData` has to provide the unique identifier of each participating
feed's public keys.

To reduce the calldata load, Scribe does not use type `address`, which uses 20
bytes per feed, but encodes the unique feeds' byte-wise into a `bytes` called
`signersBlob`. For more info, see [`LibSchnorrData.sol`](../src/libs/LibSchnorrData.sol).


## About lifting feeds

Feeds MUST verify the integrity of their public key by proving the ownership of
the corresponding private key. The `lift` function therefore expects an ECDSA
signed message derived from `wat`.

If the public key is not verified, the Schnorr signature verification is
vulnerable to rogue-key attacks. For more info, see [`Schnorr.md`](./Schnorr.md#key-aggregation-for-multisignatures).

Also, the number of state-changing `lift` executions is limited to
`type(uint8).max-1`, i.e. 254. After reaching the limit, no further `lift` calls
can be executed. For more info, see [`IScribe.maxFeeds()`](../src/IScribe.sol).


## About Chainlink compatibility

Scribe provides an `IChainlinkAggregatorV3::latestRoundData()` function.
However, this function only returns the oracle's value (via `answer`) and the
value's age (via `updatedAt`). All other values are zero.


## How to verify new `opPoke`s

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
