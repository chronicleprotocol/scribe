// SPDX-License-Identifier: BUSL-1.1
// Certora Verification Language (CVL) specification for Scribe

methods {
    // Feed management
    function lift(LibSecp256k1.Point, IScribe.ECDSAData) external returns (uint8);
    function lift(LibSecp256k1.Point[], IScribe.ECDSAData[]) external returns (uint8[]);
    function drop(uint8) external;
    function drop(uint8[]) external;
    function setBar(uint8) external;

    // Auth management
    function rely(address) external;
    function deny(address) external;
    function authed(address) external returns (bool) envfree;
    function wards(address) external returns (uint256) envfree;

    // Toll management
    function kiss(address) external;
    function diss(address) external;
}

// -----------------------------------------------------------------------------
// Manual Storage Management
//
// When verifying the following rules, calling `authed(e.msg.sender)` returns a
// symbolic boolean that Certora does not automatically link to the actual
// `_wards` storage that the `auth` modifier checks.
//
// This is because the `auth` modifier uses inline assembly to read
// `_wards[msg.sender]`:
//   let slot := keccak256(0x00, 0x40)
//   let isAuthed := sload(slot)
//
// This direct `sload` is not linked to the `authed()` view function's return
// value in Certora's symbolic execution. As a result, rules using `authed()`
// may fail because the prover treats them as independent symbolic values.
//
// Therefore, a `ghostWards` ghost mapping is introduced that manually tracks
// the `_wards` via storage hooks. Note that rules should therefore use the
// `isAuthed(address)` helper function instead calling `authed(address)`
// directly on the contract.

ghost mapping(address => uint256) ghostWards {
    init_state axiom forall address a. ghostWards[a] == 0;
}

hook Sstore currentContract._wards[KEY address who] uint256 newVal (uint256 oldVal) {
    ghostWards[who] = newVal;
}

hook Sload uint256 val currentContract._wards[KEY address who] {
    require ghostWards[who] == val;
}

definition isAuthed(address who) returns bool =
    ghostWards[who] != 0;

// ----------------------------------------------------------------------------
// Rules

rule liftRevertsIfNotAuthed(env e, LibSecp256k1.Point pubKey, IScribe.ECDSAData ecdsaData) {
    bool callerAuthed = isAuthed(e.msg.sender);

    lift@withrevert(e, pubKey, ecdsaData);

    assert !callerAuthed => lastReverted;
}

rule dropRevertsIfNotAuthed(env e, uint8 feedId) {
    bool callerAuthed = isAuthed(e.msg.sender);

    drop@withrevert(e, feedId);

    assert !callerAuthed => lastReverted;
}

rule setBarRevertsIfNotAuthed(env e, uint8 newBar) {
    require newBar != 0;

    bool callerAuthed = isAuthed(e.msg.sender);

    setBar@withrevert(e, newBar);

    assert !callerAuthed => lastReverted;
}

rule relyRevertsIfNotAuthed(env e, address who) {
    bool callerAuthed = isAuthed(e.msg.sender);

    rely@withrevert(e, who);

    assert !callerAuthed => lastReverted;
}

rule denyRevertsIfNotAuthed(env e, address who) {
    bool callerAuthed = isAuthed(e.msg.sender);

    deny@withrevert(e, who);

    assert !callerAuthed => lastReverted;
}

rule kissRevertsIfNotAuthed(env e, address who) {
    bool callerAuthed = isAuthed(e.msg.sender);

    kiss@withrevert(e, who);

    assert !callerAuthed => lastReverted;
}

rule dissRevertsIfNotAuthed(env e, address who) {
    bool callerAuthed = isAuthed(e.msg.sender);

    diss@withrevert(e, who);

    assert !callerAuthed => lastReverted;
}
