// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract ImbalanceGateHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    error MaxImbalanceExceeded(PoolId poolId, int256 cumulativeDelta0, int256 cumulativeDelta1);

    uint256 public immutable MAX_ALLOWED_DELTA0;
    uint256 public immutable MAX_ALLOWED_DELTA1;

    constructor(
        IPoolManager _poolManager,
        uint256 _maxAllowedDelta0,
        uint256 _maxAllowedDelta1
    ) BaseHook(_poolManager) {
        MAX_ALLOWED_DELTA0 = _maxAllowedDelta0;
        MAX_ALLOWED_DELTA1 = _maxAllowedDelta1;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _getSlotDelta0(PoolId poolId) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, poolId)
            mstore(0x20, "v4guard.delta0")
            slot := keccak256(0x00, 0x40)
        }
    }

    function _getSlotDelta1(PoolId poolId) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, poolId)
            mstore(0x20, "v4guard.delta1")
            slot := keccak256(0x00, 0x40)
        }
    }

    function _abs(int256 x) internal pure returns (uint256 absVal) {
        assembly {
            switch slt(x, 0)
            case 1 {
                absVal := sub(0, x)
            }
            default {
                absVal := x
            }
        }
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        PoolId poolId = key.toId();
        bytes32 slot0 = _getSlotDelta0(poolId);
        bytes32 slot1 = _getSlotDelta1(poolId);

        int256 d0 = int256(delta.amount0());
        int256 d1 = int256(delta.amount1());

        assembly {
            let current0 := tload(slot0)
            let current1 := tload(slot1)

            tstore(slot0, add(current0, d0))
            tstore(slot1, add(current1, d1))
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    /// @notice Evaluează invariantul economic la granița explicită de settlement din unlockCallback
    function validateSettlementInvariant(PoolKey calldata key) external view {
        PoolId poolId = key.toId();
        bytes32 slot0 = _getSlotDelta0(poolId);
        bytes32 slot1 = _getSlotDelta1(poolId);

        int256 cum0;
        int256 cum1;

        assembly {
            cum0 := tload(slot0)
            cum1 := tload(slot1)
        }

        if (_abs(cum0) > MAX_ALLOWED_DELTA0 || _abs(cum1) > MAX_ALLOWED_DELTA1) {
            revert MaxImbalanceExceeded(poolId, cum0, cum1);
        }
    }

    /// @dev Introspection helper pentru teste și debugging
    function getAccumulatedDeltas(PoolId poolId) external view returns (int256 cum0, int256 cum1) {
        bytes32 slot0 = _getSlotDelta0(poolId);
        bytes32 slot1 = _getSlotDelta1(poolId);

        assembly {
            cum0 := tload(slot0)
            cum1 := tload(slot1)
        }
    }
}
