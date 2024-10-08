<img src="./assets/logo.png"/>

[![Unit Tests](https://github.com/chronicleprotocol/scribe/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/chronicleprotocol/scribe/actions/workflows/unit-tests.yml)

Scribe is an efficient Schnorr multi-signature based Oracle. For more info, see [docs/Scribe.md](./docs/Scribe.md).

## Bug Bounty

This repository is subject to _Chronicle Protocol_'s Bug Bounty program, per the terms defined [here](https://cantina.xyz/bounties/5240b7c7-6fec-4902-bec0-8cad12f14ec4).

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
$ forge test --nmt "FuzzDifferentialOracleSuite" # Run only non-differential fuzz tests
```

Note that in order to run the whole test suite, i.e. including differential fuzz tests, the oracle-suite's musig [`schnorr`](https://github.com/chronicleprotocol/musig/tree/master/cmd/schnorr) binary needs to be present inside the `bin/` directory.

Lint:

```bash
$ forge fmt [--check]
```

Update gas snapshots:

```bash
$ forge snapshot --nmt "Fuzz" [--check]
```

## Dependencies

- [chronicleprotocol/chronicle-std@v2](https://github.com/chronicleprotocol/chronicle-std/tree/v2)

## Licensing

The primary license for Scribe is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE). However, some files are dual licensed under `MIT`:

- All files in `src/libs/` may also be licensed under `MIT` (as indicated in their SPDX headers), see [`src/libs/LICENSE`](./src/libs/LICENSE)
- Several Solidity interface files may also be licensed under `MIT` (as indicated in their SPDX headers)
- Several files in `script/` may also be licensed under `MIT` (as indicated in their SPDX headers)
