package main

import (
	"fmt"
	"os"
)

const helpText = `Scribe Elliptic Curve Cryptography Reference Implementation (scribe-ecc-ref)

Subcommands:
	secp256k1		Provides elliptic curve operations on the Secp256k1 curve
	schnorr			Provides Schnorr signature operations

secp256k1:
	scalarMultiplication <scalar in base 10> [--debug]
	pointAddition <list of coordinates in base 10> [--debug]

schnorr:
	sign <private key in base 10> <message hash in base 16> [--debug]
	verify
	recoverSigner

For more info, see https://github.com/chronicleprotocol/scribe`

func main() {
	// Print help page if invoked with -h or --help.
	if os.Args[1] == "-h" || os.Args[1] == "--help" {
		fmt.Println(helpText)
		os.Exit(1)
	}

	// Otherwise run subcommand.
	if err := runCmd(os.Args[1:]); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
