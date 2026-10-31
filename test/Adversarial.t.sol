// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BaseHook} from "../src/BaseHook.sol";
import {TickExcursionGuard} from "../src/TickExcursionGuard.sol";
import {TickExcursionGuardHook} from "../src/TickExcursionGuardHook.sol";

/// @notice Attacker-written router: talks to the PoolManager directly, no PoolSwapTest, no settlement.
contract RawSwapRouter is IUnlockCallback {
    IPoolManager public immutable manager;
    PoolKey internal key;
    IPoolManager.SwapParams[] internal params;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function run(PoolKey calldata k, IPoolManager.SwapParams[] calldata ps) external {
        key = k;
        delete params;
        for (uint256 i; i < ps.length; i++) {
            params.push(ps[i]);
        }
        manager.unlock("");
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        for (uint256 i; i < params.length; i++) {
            manager.swap(key, params[i], "");
        }
        return ""; // deliberately never settles: we only care whether the hook stops the swap
    }
}

contract AdversarialTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint24 internal constant MAX_DEV = 50;
    int256 internal constant SMALL = -1e14;
    int256 internal constant MEDIUM = -2e15;
    int256 internal constant LARGE = -1e16;

    TickExcursionGuardHook internal hook;
    RawSwapRouter internal raw;
    PoolKey internal key2; // second 1:1 pool on the same hook
    PoolKey internal highKey; // starts at price 2 (positive tick)
    PoolKey internal lowKey; // starts at price 1/2 (negative tick)

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x6666 << 144));
        deployCodeTo("TickExcursionGuardHook.sol:TickExcursionGuardHook", abi.encode(manager, MAX_DEV), hookAddr);
        hook = TickExcursionGuardHook(hookAddr);
        raw = new RawSwapRouter(manager);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 3000, SQRT_PRICE_1_1);
        (key2,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 500, SQRT_PRICE_1_1);
        (highKey,) = initPool(currency0, currency1, IHooks(hookAddr), 10000, SQRT_PRICE_2_1);
        (lowKey,) = initPool(currency0, currency1, IHooks(hookAddr), 100, SQRT_PRICE_1_2);
        _fullRange(highKey);
        _fullRange(lowKey);
    }

    function _fullRange(PoolKey memory k) internal {
        IPoolManager.ModifyLiquidityParams memory p = LIQUIDITY_PARAMS;
        p.tickLower = TickMath.minUsableTick(k.tickSpacing);
        p.tickUpper = TickMath.maxUsableTick(k.tickSpacing);
        p.liquidityDelta = int256(1e18);
        modifyLiquidityRouter.modifyLiquidity(k, p, ZERO_BYTES);
    }

    function _hasSelector(bytes memory data, bytes4 sel) internal pure returns (bool) {
        for (uint256 i; i + 4 <= data.length; i++) {
            if (data[i] == sel[0] && data[i + 1] == sel[1] && data[i + 2] == sel[2] && data[i + 3] == sel[3]) {
                return true;
            }
        }
        return false;
    }

    function _params(bool z, int256 a) internal pure returns (IPoolManager.SwapParams memory) {
        return IPoolManager.SwapParams({
            zeroForOne: z, amountSpecified: a, sqrtPriceLimitX96: z ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
    }

    // ---- helpers that keep several actions inside one transaction ----

    function doOne(PoolKey memory k, bool z, int256 a) external {
        swap(k, z, a, ZERO_BYTES);
    }

    function swapAndReadStart(PoolKey memory k, bool z, int256 a) external returns (int24 start, bool isSet) {
        swap(k, z, a, ZERO_BYTES);
        return hook.startTickOf(k.toId());
    }

    function twoPools() external {
        swap(key, true, MEDIUM, ZERO_BYTES);
        swap(key2, true, MEDIUM, ZERO_BYTES);
    }

    function twoPoolsThenCumulative() external {
        swap(key, true, MEDIUM, ZERO_BYTES);
        swap(key2, true, MEDIUM, ZERO_BYTES);
        swap(key, true, MEDIUM, ZERO_BYTES);
    }

    function tryLargeThenMedium() external returns (int24 start) {
        try this.doOne(key, true, LARGE) {
            revert("large swap should have reverted");
        } catch {}
        swap(key, true, MEDIUM, ZERO_BYTES);
        (start,) = hook.startTickOf(key.toId());
    }

    // ---- 1. custom router, direct unlock/swap ----

    function test_RawRouter_LargeSwap_StoppedByHook() public {
        IPoolManager.SwapParams[] memory ps = new IPoolManager.SwapParams[](1);
        ps[0] = _params(true, LARGE);
        try raw.run(key, ps) {
            fail();
        } catch (bytes memory reason) {
            assertTrue(_hasSelector(reason, TickExcursionGuard.TickExcursionExceeded.selector), "not stopped by hook");
        }
    }

    function test_RawRouter_SmallThenLargeInOneUnlock_StoppedByHook() public {
        IPoolManager.SwapParams[] memory ps = new IPoolManager.SwapParams[](2);
        ps[0] = _params(true, SMALL);
        ps[1] = _params(true, LARGE);
        try raw.run(key, ps) {
            fail();
        } catch (bytes memory reason) {
            assertTrue(_hasSelector(reason, TickExcursionGuard.TickExcursionExceeded.selector), "not stopped by hook");
        }
    }

    function test_RawRouter_SmallSwap_NotBlockedByHook() public {
        IPoolManager.SwapParams[] memory ps = new IPoolManager.SwapParams[](1);
        ps[0] = _params(true, SMALL);
        try raw.run(key, ps) {
            fail(); // unsettled deltas must still revert in the PoolManager
        } catch (bytes memory reason) {
            assertFalse(
                _hasSelector(reason, TickExcursionGuard.TickExcursionExceeded.selector), "hook blocked a small swap"
            );
        }
    }

    // ---- 2. callbacks cannot be driven directly ----

    function test_DirectBeforeSwapCall_Reverts() public {
        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), key, _params(true, SMALL), "");
    }

    function test_DirectAfterSwapCall_Reverts() public {
        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterSwap(address(this), key, _params(true, SMALL), BalanceDelta.wrap(0), "");
    }

    // ---- 3. non-zero start ticks (transient packing of signed ticks) ----

    function test_PositiveStartTick_RecordedExactlyAndEnforced() public {
        (, int24 t0,,) = manager.getSlot0(highKey.toId());
        assertGt(t0, 0);
        (int24 s, bool set) = this.swapAndReadStart(highKey, true, SMALL);
        assertTrue(set);
        assertEq(s, t0);
        vm.expectRevert();
        this.doOne(highKey, true, LARGE);
    }

    function test_NegativeStartTick_RecordedExactlyAndEnforced() public {
        (, int24 t0,,) = manager.getSlot0(lowKey.toId());
        assertLt(t0, 0);
        (int24 s, bool set) = this.swapAndReadStart(lowKey, false, SMALL);
        assertTrue(set);
        assertEq(s, t0);
        vm.expectRevert();
        this.doOne(lowKey, false, LARGE);
    }

    // ---- 4. exact-output swaps ----

    function test_ExactOutput_Small_Passes() public {
        this.doOne(highKey, true, 1e14);
    }

    function test_ExactOutput_Large_Reverts() public {
        vm.expectRevert();
        this.doOne(highKey, true, 1e16);
    }

    // ---- 5. several pools in one transaction ----

    function test_TwoPools_HaveIndependentBudgets() public {
        this.twoPools();
    }

    function test_TwoPools_CumulativeOnOnePool_Reverts() public {
        vm.expectRevert();
        this.twoPoolsThenCumulative();
    }

    // ---- 6. a reverted swap caught with try/catch does not poison transient state ----

    function test_CaughtRevert_DoesNotCorruptStartTick() public {
        int24 start = this.tryLargeThenMedium();
        assertEq(start, 0, "start tick must be the real pre-transaction tick");
    }
}
