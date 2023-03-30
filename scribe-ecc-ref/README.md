# Scribe Elliptic Curve Cryptography Reference Implementation

## Compilation

The project uses the go programming language. You can find installation instructions [here](https://golang.org).

```bash
$ go build . # If dependencies are missing, install them via `go get ...`
```

## Usage

```bash
$ ./scribe-ecc-ref -h
> Scribe Elliptic Curve Cryptography Reference Implementation (scribe-ecc-ref)
>
> Subcommands:
> 	  secp256k1		    Provides elliptic curve operations on the Secp256k1 curve
> 	  schnorr			Provides Schnorr signature operations
>
> secp256k1:
> 	  scalarMultiplication <scalar in base 10> [--debug]
> 	  pointAddition <list of coordinates in base 10> [--debug]
>
> schnorr:
> 	  sign <private key in base 10> <message hash in base 16> [--debug]
> 	  verify
> 	  recoverSigner
>
> For more info, see https://github.com/chronicleprotocol/scribe
```
