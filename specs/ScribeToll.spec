// SPDX-License-Identifier: BUSL-1.1
// Certora Verification Language (CVL) specification for Scribe

methods {
    // Read functions
    function read() external returns (uint256);
    function tryRead() external returns (bool, uint256);
    function readWithAge() external returns (uint256, uint256);
    function tryReadWithAge() external returns (bool, uint256, uint256);
    function peek() external returns (uint256, bool);
    function peep() external returns (uint256, bool);
    function latestRoundData() external returns (uint80, int256, uint256, uint256, uint80);
    function latestAnswer() external returns (int256);

    // Toll management
    function tolled(address) external returns (bool) envfree;
    function bud(address) external returns (uint256) envfree;
}

// -----------------------------------------------------------------------------
// Manual Storage Management
//
// When verifying the following rules, calling `tolled(e.msg.sender)` returns a
// symbolic boolean that Certora does not automatically link to the actual
// `_buds` storage that the `toll` modifier checks.
//
// This is because the `toll` modifier uses inline assembly to read
// `_buds[msg.sender]`:
//   let slot := keccak256(0x00, 0x40)
//   let isTolled := sload(slot)
//
// This direct `sload` is not linked to the `tolled()` view function's return
// value in Certora's symbolic execution. As a result, rules using `tolled()`
// may fail because the prover treats them as independent symbolic values.
//
// Therefore, a `ghostBuds` ghost mapping is introduced that manually tracks
// the `_buds` via storage hooks. Note that rules should therefore use the
// `isTolled(address)` helper function instead calling `tolled(address)`
// directly on the contract.

ghost mapping(address => uint256) ghostBuds {
    init_state axiom forall address a. ghostBuds[a] == 0;
}

hook Sstore currentContract._buds[KEY address who] uint256 newVal (uint256 oldVal) {
    ghostBuds[who] = newVal;
}

hook Sload uint256 val currentContract._buds[KEY address who] {
    require ghostBuds[who] == val;
}

definition isTolled(address who) returns bool =
    ghostBuds[who] != 0;

// ----------------------------------------------------------------------------

rule readRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    read@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule tryReadRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    tryRead@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule readWithAgeRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    readWithAge@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule tryReadWithAgeRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    tryReadWithAge@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule peekRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    peek@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule peepRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    peep@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule latestRoundDataRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    latestRoundData@withrevert(e);

    assert !callerTolled => lastReverted;
}

rule latestAnswerRevertsIfNotTolled(env e) {
    bool callerTolled = isTolled(e.msg.sender);

    latestAnswer@withrevert(e);

    assert !callerTolled => lastReverted;
}
