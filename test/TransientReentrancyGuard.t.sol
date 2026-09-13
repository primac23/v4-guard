// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransientReentrancyGuard} from "../src/TransientReentrancyGuard.sol";

contract GuardHarness is TransientReentrancyGuard {
    uint256 public counter;

    function normalCall() external nonReentrantTransient {
        counter += 1;
    }

    function recursiveCall(uint256 depth) external nonReentrantTransient {
        counter += 1;
        if (depth > 0) {
            this.recursiveCall(depth - 1);
        }
    }

    function crossFunctionReentrancy() external nonReentrantTransient {
        this.normalCall();
    }
}

contract TransientReentrancyGuardTest is Test {
    GuardHarness internal harness;

    function setUp() public {
        harness = new GuardHarness();
    }

    function test_AllowSequentialCalls() public {
        harness.normalCall();
        harness.normalCall();
        assertEq(harness.counter(), 2);
    }

    function test_RevertOn_DirectRecursion() public {
        vm.expectRevert(TransientReentrancyGuard.ReentrantCall.selector);
        harness.recursiveCall(1);
    }

    function test_RevertOn_CrossFunctionReentrancy() public {
        vm.expectRevert(TransientReentrancyGuard.ReentrantCall.selector);
        harness.crossFunctionReentrancy();
    }

    function testFuzz_TransientSlotClearsAfterExecution(uint8 runs) public {
        for (uint256 i = 0; i < runs; i++) {
            harness.normalCall();
        }
        assertEq(harness.counter(), runs);
    }
}
