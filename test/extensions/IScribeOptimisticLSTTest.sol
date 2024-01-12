// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IToll} from "chronicle-std/toll/IToll.sol";

import {IScribeOptimisticLST} from "src/extensions/IScribeOptimisticLST.sol";

import {IScribeOptimisticTest} from "../IScribeOptimisticTest.sol";

abstract contract IScribeOptimisticLSTTest is IScribeOptimisticTest {
    IScribeOptimisticLST private opScribeLST;

    function setUp(address scribe_) internal override(IScribeOptimisticTest) {
        super.setUp(scribe_);

        opScribeLST = IScribeOptimisticLST(scribe_);
    }

    function test_getAPR_DoesNotRevertIf_ValIsZero() public {
        uint val = opScribeLST.getAPR();
        assertEq(val, 0);
    }

    // -- Test: Toll Protected Functions --

    function test_getAPR_isTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        opScribeLST.getAPR();
    }
}
