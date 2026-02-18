// SPDX-License-Identifier: BUSL-1.1
// Certora Verification Language (CVL) specification for Scribe

methods {
    function poke(IScribe.PokeData, IScribe.SchnorrData) external;
    function poke_optimized_7136211(IScribe.PokeData, IScribe.SchnorrData) external;
    function bar() external returns (uint8) envfree;
}

// -----------------------------------------------------------------------------
// Ghost Storage Management

ghost uint128 ghostPokeDataVal {
    init_state axiom ghostPokeDataVal == 0;
}

ghost uint32 ghostPokeDataAge {
    init_state axiom ghostPokeDataAge == 0;
}

hook Sstore currentContract._pokeData.val uint128 newVal (uint128 oldVal) {
    ghostPokeDataVal = newVal;
}

hook Sload uint128 val currentContract._pokeData.val {
    require ghostPokeDataVal == val;
}

hook Sstore currentContract._pokeData.age uint32 newAge (uint32 oldAge) {
    ghostPokeDataAge = newAge;
}

hook Sload uint32 age currentContract._pokeData.age {
    require ghostPokeDataAge == age;
}

// -----------------------------------------------------------------------------
// Helper Functions

definition isNotPoke(method f) returns bool =
    f.selector != sig:poke(IScribe.PokeData, IScribe.SchnorrData).selector &&
    f.selector != sig:poke_optimized_7136211(IScribe.PokeData, IScribe.SchnorrData).selector;

// -----------------------------------------------------------------------------
// Rules

/// @dev Verifies every value has an age.
invariant valueImpliesAge()
    ghostPokeDataVal != 0 => ghostPokeDataAge != 0;

/// @dev Verifies no non-poke function updates the poke data.
rule onlyPokeCanMutatePokeData(method f, env e, calldataarg args)
    filtered { f -> !f.isView && !f.isFallback && isNotPoke(f) }
{
    uint128 valBefore = ghostPokeDataVal;
    uint32 ageBefore = ghostPokeDataAge;

    f(e, args);

    assert ghostPokeDataVal == valBefore;
    assert ghostPokeDataAge == ageBefore;
}

/// @dev Verifies poke reverts if length of `feedIds` does not match bar.
rule pokeRevertsIfBarNotReached(env e, IScribe.PokeData pokeData, IScribe.SchnorrData schnorrData) {
    require schnorrData.feedIds.length != to_mathint(bar());

    poke@withrevert(e, pokeData, schnorrData);

    assert lastReverted;
}
