// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract PersistentImbalanceGateHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    error MaxImbalanceExceeded(PoolId poolId, int256 cumulativeDelta0, int256 cumulativeDelta1);

    uint256 public immutable MAX_ALLOWED_DELTA0;
    uint256 public immutable MAX_ALLOWED_DELTA1;

    mapping(bytes32 => int256) public storageSlots;

    constructor(IPoolManager _poolManager, uint256 _maxAllowedDelta0, uint256 _maxAllowedDelta1)
        BaseHook(_poolManager)
    {
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
            mstore(0x20, "v4guard.persistent.delta0")
            slot := keccak256(0x00, 0x40)
        }
    }

    function _getSlotDelta1(PoolId poolId) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, poolId)
            mstore(0x20, "v4guard.persistent.delta1")
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

        storageSlots[slot0] += int256(delta.amount0());
        storageSlots[slot1] += int256(delta.amount1());

        return (BaseHook.afterSwap.selector, 0);
    }

    function validateSettlementInvariant(PoolKey calldata key) external {
        PoolId poolId = key.toId();
        bytes32 slot0 = _getSlotDelta0(poolId);
        bytes32 slot1 = _getSlotDelta1(poolId);

        int256 cum0 = storageSlots[slot0];
        int256 cum1 = storageSlots[slot1];

        // Curățare storage persistentă pentru tranzacții viitoare (emulare cost curățare / dirty storage)
        storageSlots[slot0] = 0;
        storageSlots[slot1] = 0;

        if (_abs(cum0) > MAX_ALLOWED_DELTA0 || _abs(cum1) > MAX_ALLOWED_DELTA1) {
            revert MaxImbalanceExceeded(poolId, cum0, cum1);
        }
    }
}
