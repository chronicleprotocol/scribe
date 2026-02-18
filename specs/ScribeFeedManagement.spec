// SPDX-License-Identifier: BUSL-1.1
// Certora Verification Language (CVL) specification for Scribe

methods {
    function lift(LibSecp256k1.Point, IScribe.ECDSAData) external returns (uint8);
    function lift(LibSecp256k1.Point[], IScribe.ECDSAData[]) external returns (uint8[]);
    function drop(uint8) external;
    function drop(uint8[]) external;
    function feeds(address) external returns (bool) envfree;
    function feeds(uint8) external returns (bool, address) envfree;
}

// -----------------------------------------------------------------------------
// Ghost Storage Management

ghost mapping(uint256 => uint256) ghostPubKeysX {
    init_state axiom forall uint256 id. ghostPubKeysX[id] == 0;
}

ghost mapping(uint256 => uint256) ghostPubKeysY {
    init_state axiom forall uint256 id. ghostPubKeysY[id] == 0;
}

hook Sstore currentContract._pubKeys[INDEX uint256 id].x uint256 newX (uint256 oldX) {
    ghostPubKeysX[id] = newX;
}

hook Sload uint256 x currentContract._pubKeys[INDEX uint256 id].x {
    require ghostPubKeysX[id] == x;
}

hook Sstore currentContract._pubKeys[INDEX uint256 id].y uint256 newY (uint256 oldY) {
    ghostPubKeysY[id] = newY;
}

hook Sload uint256 y currentContract._pubKeys[INDEX uint256 id].y {
    require ghostPubKeysY[id] == y;
}

// -----------------------------------------------------------------------------
// Helper Functions

definition isNotLiftOrDrop(method f) returns bool =
    f.selector != sig:lift(LibSecp256k1.Point, IScribe.ECDSAData).selector &&
    f.selector != sig:lift(LibSecp256k1.Point[], IScribe.ECDSAData[]).selector &&
    f.selector != sig:drop(uint8).selector &&
    f.selector != sig:drop(uint8[]).selector;

// -----------------------------------------------------------------------------
// Rules

/// @dev Verifies no non-lift/drop function updates feeds.
rule onlyLiftAndDropCanMutatePubKeys(method f, env e, calldataarg args, uint8 feedId)
    filtered { f -> !f.isView && !f.isFallback && isNotLiftOrDrop(f) }
{
    uint256 pubKeyXBefore = ghostPubKeysX[feedId];
    uint256 pubKeyYBefore = ghostPubKeysY[feedId];

    f(e, args);

    assert ghostPubKeysX[feedId] == pubKeyXBefore;
    assert ghostPubKeysY[feedId] == pubKeyYBefore;
}
