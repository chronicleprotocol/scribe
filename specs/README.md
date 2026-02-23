# Certora Specification

This directory provides specifications for the `Scribe` oracle contract symbolically proven by the [Certora Prover](https://www.certora.com/prover).

## Usage

The specification is written in `CVL`, the Certora Verification Language.

### Prerequisites

1. Install the Certora Prover CLI:
```bash
$ pip install certora-cli
```

2. Set your Certora key:
```bash
$ export CERTORAKEY=<your-certora-key>
```

### Running Specifications

Run individual specifications using `certoraRun` with the corresponding `.conf` file:

```bash
# Auth invariants
$ certoraRun specs/ScribeAuth.conf

# Feed management invariants
$ certoraRun specs/ScribeFeedManagement.conf

# Poke invariants
$ certoraRun specs/ScribePoke.conf

# Toll invariants
$ certoraRun specs/ScribeToll.conf
```
