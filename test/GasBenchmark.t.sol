// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ImbalanceGateHook} from "../src/ImbalanceGateHook.sol";
import {PersistentImbalanceGateHook} from "../src/PersistentImbalanceGateHook.sol";

contract BenchmarkPoolManager {
    bool private locked;

    function unlock(bytes calldata data) external returns (bytes memory result) {
        locked = true;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        locked = false;
    }

    function dispatchAfterSwap(address hookAddress, PoolKey calldata key, BalanceDelta delta)
        external
        returns (bytes4, int128)
    {
        IPoolManager.SwapParams memory emptyParams;
        return IHooks(hookAddress).afterSwap(msg.sender, key, emptyParams, delta, "");
    }
}

contract BenchmarkRouter is IUnlockCallback {
    BenchmarkPoolManager public immutable manager;

    struct ExecutionPayload {
        address hook;
        PoolKey key;
        uint256 swapCount;
        bool isPersistent;
    }

    constructor(BenchmarkPoolManager _manager) {
        manager = _manager;
    }

    function runBenchmark(address hook, PoolKey calldata key, uint256 swapCount, bool isPersistent) external {
        manager.unlock(
            abi.encode(ExecutionPayload({hook: hook, key: key, swapCount: swapCount, isPersistent: isPersistent}))
        );
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        ExecutionPayload memory p = abi.decode(data, (ExecutionPayload));

        for (uint256 i = 0; i < p.swapCount; i++) {
            BalanceDelta delta = toBalanceDelta(10, -9);
            if (p.hook != address(0)) {
                manager.dispatchAfterSwap(p.hook, p.key, delta);
            }
        }

        if (p.hook != address(0)) {
            if (p.isPersistent) {
                PersistentImbalanceGateHook(p.hook).validateSettlementInvariant(p.key);
            } else {
                ImbalanceGateHook(p.hook).validateSettlementInvariant(p.key);
            }
        }

        return "";
    }
}

contract GasBenchmarkTest is Test {
    BenchmarkPoolManager internal manager;
    BenchmarkRouter internal router;
    address internal transientHook;
    address internal persistentHook;
    PoolKey internal tKey;
    PoolKey internal pKey;
    PoolKey internal bKey;

    function setUp() public {
        manager = new BenchmarkPoolManager();
        router = new BenchmarkRouter(manager);

        // Setup Transient Hook
        address tAddr = address(uint160(Hooks.AFTER_SWAP_FLAG));
        ImbalanceGateHook tImpl = new ImbalanceGateHook(IPoolManager(address(manager)), 100000, 100000);
        vm.etch(tAddr, address(tImpl).code);
        transientHook = tAddr;

        // Setup Persistent Hook
        address pAddr = address(uint160(Hooks.AFTER_SWAP_FLAG | 0x100));
        PersistentImbalanceGateHook pImpl =
            new PersistentImbalanceGateHook(IPoolManager(address(manager)), 100000, 100000);
        vm.etch(pAddr, address(pImpl).code);
        persistentHook = pAddr;

        tKey = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 3000, 60, IHooks(transientHook));
        pKey = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 3000, 60, IHooks(persistentHook));
        bKey = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 3000, 60, IHooks(address(0)));
    }

    function _benchmarkSwaps(uint256 count) internal {
        uint256 g0 = gasleft();
        router.runBenchmark(address(0), bKey, count, false);
        uint256 baselineGas = g0 - gasleft();

        uint256 g1 = gasleft();
        router.runBenchmark(transientHook, tKey, count, false);
        uint256 transientGas = g1 - gasleft();

        uint256 g2 = gasleft();
        router.runBenchmark(persistentHook, pKey, count, true);
        uint256 persistentGas = g2 - gasleft();

        console.log("=== Swaps count: %s ===", count);
        console.log("Baseline gas:   ", baselineGas);
        console.log("Transient gas:  ", transientGas);
        console.log("Persistent gas: ", persistentGas);
        console.log("Delta Saved (Persistent - Transient):", persistentGas - transientGas);
    }

    function test_Benchmark_1_Swap() public {
        _benchmarkSwaps(1);
    }

    function test_Benchmark_2_Swaps() public {
        _benchmarkSwaps(2);
    }

    function test_Benchmark_5_Swaps() public {
        _benchmarkSwaps(5);
    }

    function test_Benchmark_10_Swaps() public {
        _benchmarkSwaps(10);
    }

    function test_Benchmark_20_Swaps() public {
        _benchmarkSwaps(20);
    }
}
