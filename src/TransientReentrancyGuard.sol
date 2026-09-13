// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract TransientReentrancyGuard {
    error ReentrantCall();

    bytes32 private constant REENTRANCY_GUARD_SLOT = 
        0x8e8a60e0a9d0a68d0e768e7b165b4c4897f26c91e1d0342674e1d7cf9d1a3c00;

    modifier nonReentrantTransient() {
        _enterTransient();
        _;
        _exitTransient();
    }

    function _enterTransient() internal {
        bool isReentrant;
        assembly {
            isReentrant := tload(REENTRANCY_GUARD_SLOT)
            tstore(REENTRANCY_GUARD_SLOT, 1)
        }
        if (isReentrant) {
            revert ReentrantCall();
        }
    }

    function _exitTransient() internal {
        assembly {
            tstore(REENTRANCY_GUARD_SLOT, 0)
        }
    }
}
