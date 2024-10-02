# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org/).

[2.0.1]: https://github.com/chronicleprotocol/scribe/releases/tag/v2.0.1
[2.0.0]: https://github.com/chronicleprotocol/scribe/releases/tag/v2.0.0
[1.2.0]: https://github.com/chronicleprotocol/scribe/releases/tag/v1.2.0
[1.1.0]: https://github.com/chronicleprotocol/scribe/releases/tag/v1.1.0
[1.0.0]: https://github.com/chronicleprotocol/scribe/releases/tag/v1.0.0

## [2.0.1] - 2024-10-03

### Added

- Security notice about rogue key vulnerability during lift and requirement for additional external verification ([0ef985b](https://github.com/chronicleprotocol/scribe/commit/0ef985baebc2945017bff811bb65a883f565fc4f))

## [2.0.0] - 2023-11-27

### Changed

- **Breaking** Use 1-byte identifier for feeds based on highest-order byte of their addresses instead of their storage array's index ([#23](https://github.com/chronicleprotocol/scribe/pull/23))
- **Breaking** Change `IScribe` and `IScribeOptimistic` interfaces to account for new feed identification ([#23](https://github.com/chronicleprotocol/scribe/pull/23))

### Fixed

- DOS vector in `ScribeOptimistic::opPoke` making `ScribeOptimistic::opChallenge` economically unprofitable ([#23](https://github.com/chronicleprotocol/scribe/pull/23))
- Possibility to successfully `opChallenge` a valid `opPoke` via non-default calldata encoding ([#23](https://github.com/chronicleprotocol/scribe/pull/23))

## [1.2.0] - 2023-09-29

### Added

- Chainlink compatibility function `latestAnswer()(int)` ([#24](https://github.com/chronicleprotocol/scribe/pull/24))

## [1.1.0] - 2023-08-25

### Fixes

- Broken compilation without `--via-ir` pipeline ([#13](https://github.com/chronicleprotocol/scribe/pull/13))

### Added

- MakerDAO compatibility function `peep()(uint,bool)` ([#12](https://github.com/chronicleprotocol/scribe/pull/12))

## [1.0.0] - 2023-08-14

### Added

- Initial release
