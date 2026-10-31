// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @notice Swap gas on the real PoolManager: identical pools with and without TickExcursionGuardHook.
///         Each case runs in its own test from the same setUp state.
contract GasBenchmarkV2Test is Test, Deployers {
    PoolKey internal plainKey;
    PoolKey internal guardKey;
    int256 internal constant AMOUNT = -1e14; // exact input, alternating direction, never hits the bound

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        deployCodeTo("TickExcursionGuardHook.sol:TickExcursionGuardHook", abi.encode(manager, uint24(50)), hookAddr);
        (plainKey,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        (guardKey,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 3000, SQRT_PRICE_1_1);
    }

    function runSwaps(PoolKey calldata k, uint256 n) external {
        for (uint256 i; i < n; i++) {
            swap(k, i % 2 == 0, AMOUNT, ZERO_BYTES);
        }
    }

    function _measure(string memory arm, PoolKey memory k, uint256 n) internal {
        uint256 g = gasleft();
        this.runSwaps(k, n);
        uint256 used = g - gasleft();
        console.log(string.concat("BENCH,", arm, ",", vm.toString(n), ",", vm.toString(used)));
    }

    function test_bench_plain_1() public {
        _measure("plain", plainKey, 1);
    }

    function test_bench_guard_1() public {
        _measure("guard", guardKey, 1);
    }

    function test_bench_plain_2() public {
        _measure("plain", plainKey, 2);
    }

    function test_bench_guard_2() public {
        _measure("guard", guardKey, 2);
    }

    function test_bench_plain_5() public {
        _measure("plain", plainKey, 5);
    }

    function test_bench_guard_5() public {
        _measure("guard", guardKey, 5);
    }
}
