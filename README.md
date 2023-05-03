<img align="right" width="200" height="250" top="100" src="./assets/logo.jpeg">

# Scribe • [![Unit Tests](https://github.com/chronicleprotocol/scribe/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/chronicleprotocol/scribe/actions/workflows/unit-tests.yml)

Scribe is an efficient Schnorr multi-signature based Oracle.

The Schnorr signature scheme is specified in [here](./spec/Schnorr.md).

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
$ yarn install # Installs dependencies for vector-based tests
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
$ forge snapshot --nmt "Fuzz" [--check]
```
