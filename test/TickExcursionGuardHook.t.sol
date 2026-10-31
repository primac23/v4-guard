// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract TickExcursionGuardHookTest is Test, Deployers {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    uint24 internal constant MAX_DEV = 50;
    int256 internal constant SMALL = -1e14; // exact-in, ~2 ticks
    int256 internal constant MEDIUM = -2e15; // exact-in, ~40 ticks
    int256 internal constant LARGE = -1e16; // far beyond MAX_DEV

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        deployCodeTo("TickExcursionGuardHook.sol:TickExcursionGuardHook", abi.encode(manager, MAX_DEV), hookAddr);
        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 3000, SQRT_PRICE_1_1);
    }

    // Wrapping swaps in one external call keeps them inside a single transaction,
    // with or without Foundry's isolate mode.
    function doSwaps(bool[] calldata zeroForOne, int256[] calldata amounts) external {
        for (uint256 i; i < amounts.length; i++) {
            swap(key, zeroForOne[i], amounts[i], ZERO_BYTES);
        }
    }

    function doOne(bool zeroForOne, int256 amount) external {
        swap(key, zeroForOne, amount, ZERO_BYTES);
    }

    function _two(bool z1, int256 a1, bool z2, int256 a2) internal {
        bool[] memory z = new bool[](2);
        int256[] memory a = new int256[](2);
        (z[0], z[1], a[0], a[1]) = (z1, z2, a1, a2);
        this.doSwaps(z, a);
    }

    function test_SmallSwap_Passes() public {
        this.doOne(true, SMALL);
    }

    function test_SingleMediumSwap_Passes() public {
        this.doOne(true, MEDIUM);
    }

    function test_SingleLargeSwap_Reverts() public {
        vm.expectRevert();
        this.doOne(true, LARGE);
    }

    /// Flash-loan style round trip: net flow ~0, which ImbalanceGateHook allowed.
    function test_RoundTripManipulation_SameTx_Reverts() public {
        vm.expectRevert();
        _two(true, LARGE, false, LARGE);
    }

    /// Two moves that are each within bounds but cumulatively exceed it in one tx.
    function test_CumulativeExcursion_SameTx_Reverts() public {
        vm.expectRevert();
        _two(true, MEDIUM, true, MEDIUM);
    }

    /// Normal arbitrage-sized out-and-back stays within bounds.
    function test_BoundedOutAndBack_SameTx_Passes() public {
        _two(true, MEDIUM, false, MEDIUM);
    }

    function testFuzz_TickNeverExceedsBound(uint256 amt, bool zeroForOne) public {
        amt = bound(amt, 1e9, 5e16);
        try this.doOne(zeroForOne, -int256(amt)) {
            (, int24 tick,,) = manager.getSlot0(key.toId());
            int24 absTick = tick < 0 ? -tick : tick;
            assertLe(uint24(absTick), MAX_DEV);
        } catch {}
    }
}
