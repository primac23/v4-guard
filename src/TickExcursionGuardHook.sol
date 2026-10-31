// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./BaseHook.sol";
import {TickExcursionGuard} from "./TickExcursionGuard.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @title TickExcursionGuardHook
/// @notice Standalone hook: bounds how far a pool's tick may move from the first tick observed in the current
///         transaction. Checked after every swap, so it cannot be bypassed by the caller's unlock callback.
/// @dev No owner, no configuration, no persistent storage. The bound is fixed per deployment.
contract TickExcursionGuardHook is BaseHook, TickExcursionGuard {
    using PoolIdLibrary for PoolKey;

    uint24 public immutable MAX_TICK_DEVIATION;

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

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _recordStartTick(POOL_MANAGER, key.toId());
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        _enforceTickExcursion(POOL_MANAGER, key.toId(), MAX_TICK_DEVIATION);
        return (BaseHook.afterSwap.selector, 0);
    }

    /// @notice Start tick recorded for this pool in the current transaction (0, false if none yet).
    function startTickOf(PoolId poolId) external view returns (int24 startTick, bool isSet) {
        return _startTickOf(poolId);
    }
}
