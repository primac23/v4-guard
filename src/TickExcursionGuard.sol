// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/// @title TickExcursionGuard
/// @notice Inheritable building block that bounds how far a pool's tick can move within one transaction.
///         A pool can only have one hook, so existing hooks can add the protection to their own callbacks:
///         call `_recordStartTick` at the start of beforeSwap and `_enforceTickExcursion` at the end of afterSwap.
/// @dev Transaction-scoped (EIP-1153). Both functions must be wired; `_enforceTickExcursion` assumes the start
///      tick was recorded in the same transaction.
abstract contract TickExcursionGuard {
    using StateLibrary for IPoolManager;

    error TickExcursionExceeded(PoolId poolId, int24 startTick, int24 currentTick, uint24 maxDeviation);

    uint256 private constant SET_FLAG = 1 << 255;

    function _excursionSlot(PoolId poolId) private pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, poolId)
            mstore(0x20, "v4guard.tickExcursion.v1")
            slot := keccak256(0x00, 0x40)
        }
    }

    /// @notice Stores the pool's tick before the first swap on it in the current transaction.
    function _recordStartTick(IPoolManager manager, PoolId poolId) internal {
        bytes32 slot = _excursionSlot(poolId);
        uint256 packed;
        assembly {
            packed := tload(slot)
        }
        if (packed == 0) {
            (, int24 tick,,) = manager.getSlot0(poolId);
            packed = SET_FLAG | uint256(uint24(tick));
            assembly {
                tstore(slot, packed)
            }
        }
    }

    /// @notice Reverts if the pool's tick is more than `maxDeviation` ticks away from the recorded start tick.
    function _enforceTickExcursion(IPoolManager manager, PoolId poolId, uint24 maxDeviation) internal view {
        bytes32 slot = _excursionSlot(poolId);
        uint256 packed;
        assembly {
            packed := tload(slot)
        }
        int24 startTick = int24(uint24(packed));
        (, int24 tick,,) = manager.getSlot0(poolId);
        int256 diff = int256(tick) - int256(startTick);
        if (diff < 0) diff = -diff;
        if (uint256(diff) > maxDeviation) revert TickExcursionExceeded(poolId, startTick, tick, maxDeviation);
    }

    /// @notice Start tick recorded for `poolId` in the current transaction.
    function _startTickOf(PoolId poolId) internal view returns (int24 startTick, bool isSet) {
        bytes32 slot = _excursionSlot(poolId);
        uint256 packed;
        assembly {
            packed := tload(slot)
        }
        return (int24(uint24(packed)), packed != 0);
    }
}
