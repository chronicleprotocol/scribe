<img src="./assets/logo.png"/>

[![Unit Tests](https://github.com/chronicleprotocol/scribe/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/chronicleprotocol/scribe/actions/workflows/unit-tests.yml)

Scribe is an efficient Schnorr multi-signature based Oracle. For more info, see [docs/Scribe.md](./docs/Scribe.md).

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
$ forge test # Run all tests, including differential fuzzing tests
$ forge test -vvvv # Run all tests with full stack traces
$ FOUNDRY_PROFILE=intense forge test # Run all tests in intense mode
$ forge test --nmt "FuzzDifferential(OracleSuite|Dissig)" # Run only non-differential fuzz tests
```

Note that in order to run the whole test suite, i.e. including differential fuzzing tests, the [`dissig`]() and oracle-suite's [`schnorr`]() binaries need to be present inside the `bin/` directory.

Lint:
```bash
$ forge fmt [--check]
```

Update gas snapshots:
```bash
$ forge snapshot --nmt "Fuzz" [--check]
```
