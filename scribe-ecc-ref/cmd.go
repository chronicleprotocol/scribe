package main

import (
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"

	"github.com/chronicleprotocol/scribe/scribe-ecc-ref/secp256k1"

	"github.com/btcsuite/btcd/btcec/v2"
	"github.com/btcsuite/btcd/btcec/v2/schnorr"
)

type CmdRunner interface {
	Run([]string) error
	Name() string
}

func runCmd(args []string) error {
	if len(args) < 1 {
		return errors.New("missing subcommand")
	}

	cmds := []CmdRunner{
		NewSecp256k1Command(),
		NewSchnorrCommand(),
	}

	subcmd := os.Args[1]

	for _, cmd := range cmds {
		if cmd.Name() == subcmd {
			return cmd.Run(os.Args[2:])
		}
	}

	return fmt.Errorf("unknown subsommand: %s", subcmd)
}

type Secp256k1Command struct{}

func NewSecp256k1Command() *Secp256k1Command {
	return &Secp256k1Command{}
}

func (cmd *Secp256k1Command) Name() string {
	return "secp256k1"
}

func (cmd *Secp256k1Command) Run(args []string) error {
	subcmd := args[0]

	// Check if --debug argument given.
	// If so, set internal flag and remove argument from set.
	debug := false
	for i, arg := range args {
		if arg == "--debug" {
			debug = true
			// Remove --debug argument from args list.
			args = append(args[:i], args[i+1:]...)
		}
	}

	switch subcmd {
	case "scalarMultiplication":
		// Parse scalar.
		if len(args) < 2 {
			return fmt.Errorf("missing argument: scalar")
		}
		scalar, ok := new(big.Int).SetString(args[1], 10)
		if !ok {
			return fmt.Errorf("failed to parse scalar: %s", args[1])
		}

		// Compute [scalar]G on secp256k1.
		curve := secp256k1.S256()
		x, y := curve.ScalarBaseMult(scalar.Bytes())

		printPoint(x, y, debug)

	case "pointAddition":
		// Parse point coordinates.
		if len(args) < 2 {
			return fmt.Errorf("missing arguments: point coordinates")
		}
		if len(args[1:])%2 != 0 {
			return fmt.Errorf("invalid arguments: odd number of coordinates")
		}

		coordinates := []*big.Int{}
		for _, coordinateStr := range args[1:] {
			coordinate, ok := new(big.Int).SetString(coordinateStr, 10)
			if !ok {
				return fmt.Errorf("failed to parse coordinate: %s", coordinateStr)
			}

			coordinates = append(coordinates, coordinate)
		}

		// Compute of sum of points.
		curve := secp256k1.S256()
		x, y := coordinates[0], coordinates[1]
		for i := range coordinates {
			// Jump over first to coordinates
			if i == 0 || i == 1 {
				continue
			}

			// Perform addition every second step.
			// Note to use own add function.
			if i%2 == 1 {
				x, y = curve.AddReference(x, y, coordinates[i-1], coordinates[i])

				// Break early if zero point returned.
				if x.Cmp(big.NewInt(0)) == 0 && y.Cmp(big.NewInt(0)) == 0 {
					break
				}
			}
		}

		printPoint(x, y, debug)

	default:
		return fmt.Errorf("unknown secp256k1 command: %s", subcmd)

	}
	return nil
}

type SchnorrCommand struct{}

func NewSchnorrCommand() *SchnorrCommand {
	return &SchnorrCommand{}
}

func (cmd *SchnorrCommand) Name() string {
	return "schnorr"
}

func (cmd *SchnorrCommand) Run(args []string) error {
	subcmd := args[0]

	// Check if --debug argument given.
	// If so, set internal flag and remove argument from set.
	debug := false
	for i, arg := range args {
		if arg == "--debug" {
			debug = true
			// Remove --debug argument from args list.
			args = append(args[:i], args[i+1:]...)
		}
	}

	switch subcmd {
	case "sign":
		// Parse private key and message hash.
		if len(args) < 3 {
			return fmt.Errorf("missing arguments: private key, message hash")
		}
		privKeyRaw, ok := new(big.Int).SetString(args[1], 10)
		if !ok {
			return fmt.Errorf("failed to parse private key: %s", args[1])
		}
		messageHash, ok := new(big.Int).SetString(strings.TrimPrefix(args[2], "0x"), 16)
		if !ok {
			return fmt.Errorf("failed to parse message hash: %s", args[2])
		}

		// Construct btcec's private key type from private key.
		privKey, _ := btcec.PrivKeyFromBytes(privKeyRaw.Bytes())

		// Sign message hash using btcec/schnorr package.
		sig, err := schnorr.Sign(privKey, messageHash.Bytes())
		if err != nil {
			return fmt.Errorf("failed to sign message: %s", err)
		}

		// Cast signature to big int type. This ensures correct printing,
		// ie easy decoding for Solidity.
		sigAsInt := new(big.Int).SetBytes(sig.Serialize())
		fmt.Printf("%064x", sigAsInt)

	case "verify":
		break
	case "recoverSigner":
		break
	default:
		return fmt.Errorf("unknown schnorr command: %s", subcmd)
	}

	if debug {

	}

	return nil
}

func printPoint(x, y *big.Int, debug bool) {
	// If debug, print coordinates in decimal format.
	// Otherwise print in concatenated hex format with length of 64 and without
	// whitespaces. This enables Solidity to decode the output as `uint[2]`.
	if debug {
		fmt.Printf("x: %s\n", x)
		fmt.Printf("y: %s\n", y)
	} else {
		fmt.Printf("%064x", x)
		fmt.Printf("%064x", y)
	}
	fmt.Println()
}

func printSignature(sig *big.Int, debug bool) {
	if debug {

	} else {
		fmt.Printf("%064x", sig)
	}
}
