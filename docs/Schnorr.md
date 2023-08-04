# Schnorr Signature Scheme Specification

This document specifies a custom Schnorr-based signature scheme on the secp256k1
elliptic curve. The scheme is used by Chronicle Protocol's Scribe oracle contract.

## Terminology

* `H()` - Keccak256 hash function
* `‖`   - Concatenation operator, defined as `abi.encodePacked()`

* `G` - Generator of secp256k1
* `Q` - Order of secp256k1

* `x`  - The signer's private key as type `uint256`
* `P`  - The signer's public key, i.e. `[x]G`, as type `(uint256, uint256)`
* `Pₓ` - P's x coordinate as type `uint256`
* `Pₚ` - Parity of `P`'s `y` coordinate, i.e. `0` if even, `1` if odd, as type `uint8`

* `m` - Message as type `bytes32`. Note that the message **SHOULD** be a keccak256 digest
* `k` - Nonce as type `uint256`


## Signing

1. Select a _cryptographically secure_ `k ∊ [1, Q)`

   Note that `k` can be deterministically constructed via `H(x ‖ m) mod Q`.
   This construction keeps `k` random for everyone not knowing the private key
   `x` while it also ensures a nonce is never reused for different messages.

2. Compute `R = [k]G`

3. Derive `Rₑ` being the Ethereum address of `R`

   Let `Rₑ` be the _commitment_

4. Construct `e = H(Pₓ ‖ Pₚ ‖ m ‖ Rₑ) mod Q`

   Let `e` be the _challenge_

5. Compute `s = k + (e * x) mod Q`

   Let `s` be the _signature_

=> The public key `P` signs via the signature `s` and the commitment `Rₑ` the
   message `m`


## Verification

- Input : `(P, m, s, Rₑ)`
- Output: `True` if signature verification succeeds, `false` otherwise

1. Compute _challenge_ `e = H(Pₓ ‖ Pₚ ‖ m ‖ Rₑ) mod Q`

2. Compute _commitment_:
```
  [s]G - [e]P               | s = k + (e * x)
= [k + (e * x)]G - [e]P     | P = [x]G
= [k + (e * x)]G - [e * x]G | Distributive Law
= [k + (e * x) - (e * x)]G  | (e * x) - (e * x) = 0
= [k]G                      | R = [k]G
= R                         | Let ()ₑ be the Ethereum address of a Point
→ Rₑ
```

3. Verification succeeds iff `([s]G - [e]P)ₑ = Rₑ`


## Key Aggregation for Multisignatures

In order to efficiently aggregate public keys onchain, the key aggregation
mechanism for aggregated signatures is specified as the sum of the public
keys:

```
Let the signers' public keys be:
    signers = [pubKey₁, pubKey₂, ..., pubKeyₙ]

Let the aggregated public key be:
    aggPubKey = sum(signers)
              = pubKey₁     + pubKey₂     + ... + pubKeyₙ
              = [privKey₁]G + [privKey₂]G + ... + [privKeyₙ]G
              = [privKey₁   + privKey₂    + ... + privKeyₙ]G
```

Note that this aggregation scheme is vulnerable to rogue-key attacks[^musig2-paper]!
In order to prevent such attacks, it **MUST** be verified that participating
public keys own the corresponding private key.

Note further that this aggregation scheme is vulnerable to public keys with
linear relationships. A set of public keys `A` leaking the sum of their private
keys would allow the creation of a second set of public keys `B` with
`aggPubKey(A) = aggPubKey(B)`. This would make signatures created by set `A`
indistinguishable from signatures created by set `B`.
In order to prevent such issues, it **MUST** be verified that no two distinct
sets of public keys derive to the same aggregated public key. Note that
cryptographically sound created random private keys have a negligible
probability of having a linear relationship.


## Other Security Considerations

Note that the signing scheme deviates slightly from the classical Schnorr
signature scheme.

Instead of using the secp256k1 point `R = [k]G` directly, this scheme uses the
Ethereum address of the point `R`. This decreases the difficulty of
brute-forcing the signature from `256 bits` (trying random secp256k1 points)
to `160 bits` (trying random Ethereum addresses).

However, the difficulty of cracking a secp256k1 public key using the
baby-step giant-step algorithm is `O(√Q)`, with `Q` being the order of the group[^baby-step-giant-step-wikipedia].
Note that `√Q ~ 3.4e38 > 127 bit`.

Therefore, this signing scheme does not weaken the overall security.


## Implementation Optimizations

This implementation uses the ecrecover precompile to perform the necessary
elliptic curve multiplication in secp256k1 for the verification process.

The ecrecover precompile can roughly be implemented in python via[^vitalik-ethresearch-post]:
```python
def ecdsa_raw_recover(msghash, vrs):
   v, r, s = vrs
   y = # (get y coordinate for EC point with x=r, with same parity as v)
   Gz = jacobian_multiply((Gx, Gy, 1), (Q - hash_to_int(msghash)) % Q)
   XY = jacobian_multiply((r, y, 1), s)
   Qr = jacobian_add(Gz, XY)
   N = jacobian_multiply(Qr, inv(r, Q))
   return from_jacobian(N)
```

Note that ecrecover also uses `s` as variable. From this point forward, let
the Schnorr signature's `s` be `sig`.

A single ecrecover call can compute `([sig]G - [e]P)ₑ = ([k]G)ₑ = Rₑ` via the
following inputs:
```
msghash = -sig * Pₓ
v       = Pₚ + 27
r       = Pₓ
s       = Q - (e * Pₓ)
```

Note that ecrecover returns the Ethereum address of `R` and not `R` itself.

The ecrecover call then digests to:
```
Gz = [Q - (-sig * Pₓ)]G     | Double negation
   = [Q + (sig * Pₓ)]G      | Addition with Q can be removed in (mod Q)
   = [sig * Pₓ]G            | sig = k + (e * x)
   = [(k + (e * x)) * Pₓ]G

XY = [Q - (e * Pₓ)]P        | P = [x]G
   = [(Q - (e * Pₓ)) * x]G

Qr = Gz + XY                                        | Gz = [(k + (e * x)) * Pₓ]G
   = [(k + (e * x)) * Pₓ]G + XY                     | XY = [(Q - (e * Pₓ)) * x]G
   = [(k + (e * x)) * Pₓ]G + [(Q - (e * Pₓ)) * x]G

N  = Qr * Pₓ⁻¹                                                    | Qr = [(k + (e * x)) * Pₓ]G + [(Q - (e * Pₓ)) * x]G
   = [(k + (e * x)) * Pₓ]G + [(Q - (e * Pₓ)) * x]G * Pₓ⁻¹         | Distributive law
   = [(k + (e * x)) * Pₓ * Pₓ⁻¹]G + [(Q - (e * Pₓ)) * x * Pₓ⁻¹]G  | Pₓ * Pₓ⁻¹ = 1
   = [(k + (e * x))]G + [Q - e * x]G                              | sig = k + (e * x)
   = [sig]G + [Q - e * x]G                                        | Q - (e * x) = -(e * x) in (mod Q)
   = [sig]G - [e * x]G                                            | P = [x]G
   = [sig]G - [e]P
```


## Resources

- [github.com/sipa/secp256k1](https://github.com/sipa/secp256k1/blob/968e2f415a5e764d159ee03e95815ea11460854e/src/modules/schnorr/schnorr.md)
- [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
- [Analysis of Bitcoin Improvement Proposal 340](https://courses.csail.mit.edu/6.857/2020/projects/4-Elbahrawy-Lovejoy-Ouyang-Perez.pdf)

[^musig2-paper]:[MuSig2 Paper](https://eprint.iacr.org/2020/1261.pdf)
[^baby-step-giant-step-wikipedia]:[Baby-step giant-step Wikipedia](https://en.wikipedia.org/wiki/Baby-step_giant-step)
[^vitalik-ethresearch-post]:[Vitalik's ethresearch post](https://ethresear.ch/t/you-can-kinda-abuse-ecrecover-to-do-ecmul-in-secp256k1-today/2384)
