# Scribe •


## Installation

Install module via Foundry:
```bash
$ forge install chronicleprotocol/scribe
```

## Contributing

The project uses the Foundry toolchain. You can find installation instructions [here](https://getfoundry.sh/).

This repo includes a go cli tool - `scribe-ecc-ref` - to differential fuzz test
the secp256k1 and schnorr signature code against. The test suite expects this
tool to be in the `bin/` directory.

Setup:
```bash
$ git clone https://github.com/chronicleprotocol/scribe
$ cd scribe/
$ forge install
$ cd scribe-ecc-ref/
$ go build . # If dependencies are missing, install them via `got get ...`
$ cp scribe-ecc-ref ../bin
```

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
