// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./BaseHook.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @title TickExcursionGuardHook
/// @notice Bounds how far a pool's tick may move from the first tick observed in the current transaction.
///         Checked after every swap, so it cannot be bypassed by the caller's unlock callback.
/// @dev Transaction-scoped (EIP-1153). Splitting a manipulation across several transactions in the
///      same block is out of scope for this primitive.
contract TickExcursionGuardHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error TickExcursionExceeded(PoolId poolId, int24 startTick, int24 currentTick, uint24 maxDeviation);

    uint24 public immutable MAX_TICK_DEVIATION;
    uint256 private constant SET_FLAG = 1 << 255;

    constructor(IPoolManager _poolManager, uint24 _maxTickDeviation) BaseHook(_poolManager) {
        MAX_TICK_DEVIATION = _maxTickDeviation;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _slot(PoolId poolId) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, poolId)
            mstore(0x20, "v4guard.tickExcursion.v1")
            slot := keccak256(0x00, 0x40)
        }
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        bytes32 slot = _slot(poolId);
        uint256 packed;
        assembly {
            packed := tload(slot)
        }
        if (packed == 0) {
            (, int24 tick,,) = POOL_MANAGER.getSlot0(poolId);
            packed = SET_FLAG | uint256(uint24(tick));
            assembly {
                tstore(slot, packed)
            }
        }
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        bytes32 slot = _slot(poolId);
        uint256 packed;
        assembly {
            packed := tload(slot)
        }
        int24 startTick = int24(uint24(packed));
        (, int24 tick,,) = POOL_MANAGER.getSlot0(poolId);

        int256 diff = int256(tick) - int256(startTick);
        if (diff < 0) diff = -diff;
        if (uint256(diff) > MAX_TICK_DEVIATION) {
            revert TickExcursionExceeded(poolId, startTick, tick, MAX_TICK_DEVIATION);
        }
        return (BaseHook.afterSwap.selector, 0);
    }

    /// @notice Start tick recorded for this pool in the current transaction (0, false if none yet).
    function startTickOf(PoolId poolId) external view returns (int24 startTick, bool isSet) {
        bytes32 slot = _slot(poolId);
        uint256 packed;
        assembly {
            packed := tload(slot)
        }
        return (int24(uint24(packed)), packed != 0);
    }
}
