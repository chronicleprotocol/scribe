// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribeLST} from "src/extensions/IScribeLST.sol";

import {IScribeTest} from "../IScribeTest.sol";

abstract contract IScribeLSTTest is IScribeTest {
    IScribeLST private scribeLST;

    function setUp(address scribe_) internal override(IScribeTest) {
        super.setUp(scribe_);

        scribeLST = IScribeLST(scribe_);
    }

    function test_getAPR_DoesNotRevertIf_ValIsZero() public {
        uint val = scribeLST.getAPR();
        assertEq(val, 0);
    }

    // -- Test: Toll Protected Functions --

    function test_getAPR_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        scribeLST.getAPR();
    }
}
