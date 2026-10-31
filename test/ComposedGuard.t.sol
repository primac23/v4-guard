// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BaseHook} from "../src/BaseHook.sol";
import {TickExcursionGuard} from "../src/TickExcursionGuard.sol";

/// @notice Example of an existing hook with its own logic (a per-pool swap counter) that adds the guard.
contract SwapCounterGuardedHook is BaseHook, TickExcursionGuard {
    using PoolIdLibrary for PoolKey;

    uint24 public immutable MAX_DEV;
    mapping(PoolId => uint256) public swapCount;

    constructor(IPoolManager _manager, uint24 _maxDev) BaseHook(_manager) {
        MAX_DEV = _maxDev;
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
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        swapCount[id] += 1; // the hook's own logic
        _enforceTickExcursion(POOL_MANAGER, id, MAX_DEV); // the guard, last
        return (BaseHook.afterSwap.selector, 0);
    }
}

contract ComposedGuardTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    SwapCounterGuardedHook internal hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x5555 << 144));
        deployCodeTo("ComposedGuard.t.sol:SwapCounterGuardedHook", abi.encode(manager, uint24(50)), hookAddr);
        hook = SwapCounterGuardedHook(hookAddr);
        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 3000, SQRT_PRICE_1_1);
    }

    function doOne(bool zeroForOne, int256 amount) external {
        swap(key, zeroForOne, amount, ZERO_BYTES);
    }

    function test_ComposedHook_RunsItsOwnLogic() public {
        this.doOne(true, -1e14);
        assertEq(hook.swapCount(key.toId()), 1);
    }

    function test_ComposedHook_StillBlocksManipulation() public {
        vm.expectRevert();
        this.doOne(true, -1e16);
        assertEq(hook.swapCount(key.toId()), 0, "own state rolled back with the revert");
    }
}
