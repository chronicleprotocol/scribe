<img align="right" width="150" height="150" top="100" src="./assets/logo.png">

# Scribe •


## Installation

Install module via Foundry:
```bash
$ forge install chronicleprotocol/scribe
```

## Contributing

The project uses the Foundry toolchain. You can find installation instructions [here](https://getfoundry.sh/).

Setup:
```bash
$ git clone https://github.com/chronicleprotocol/scribe
$ cd scribe/
$ forge install
```

This repo includes a cli tool - `scribe-ecc-ref` - to differential fuzz test the secp256k1 and schnorr signature code against. For compilation instructions, see the [README](./scribe-ecc-ref/README.md).

After compilation, copy the binary to the `bin/` directory.

Run tests:
```bash
$ forge test
$ forge test -vvvv # Run with full stack traces
$ FOUNDRY_PROFILE=intense forge test # Run in intense mode
```

Lint:
```bash
$ forge fmt [--check]
```

Update gas snapshots:
```bash
$ forge snapshot [--check]
```
