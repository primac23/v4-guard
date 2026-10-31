# Gas benchmarks

## Setup

- Real Uniswap v4 `PoolManager` and `PoolSwapTest` router from the v4-core test utilities (`Deployers`).
- Two pools with identical parameters (0.30% fee, tick spacing 60, price 1:1, same liquidity): one without hooks, one with `TickExcursionGuardHook` (`MAX_TICK_DEVIATION = 50`).
- Each case runs in its own test from the same initial state. Swaps alternate direction with an exact input of 1e14, so the bound is never hit.
- Toolchain: forge Version: 1.8.7, solc 0.8.26, Cancun, optimizer 10,000 runs.
- Source: `test/GasBenchmarkV2.t.sol`. Reproduce with `forge test --match-contract GasBenchmarkV2Test -vv`.

## Results

| Swaps in one tx | No hook | With TickExcursionGuardHook | Overhead | Overhead per swap | Relative |
|:-:|-:|-:|-:|-:|-:|
| 1 | 149,285 | 160,917 | +11,632 | +11,632 | +7.8% |
| 2 | 228,883 | 248,261 | +19,378 | +9,689 | +8.5% |
| 5 | 404,603 | 447,353 | +42,750 | +8,550 | +10.6% |

Figures are the gas used by the whole swap call (router, PoolManager and hook), measured with `gasleft()` around the call.

## Reading the numbers

- The hook writes nothing to persistent storage, so SSTORE refunds are identical in both columns and don't affect the overhead.
- The first swap on a pool in a transaction pays for one TSTORE in `beforeSwap`. Later swaps only read it, which is why the overhead per swap goes down as the number of swaps grows.
- Most of the remaining cost is the two hook calls and the `getSlot0` reads, not transient storage.

## Change from the previous version

An earlier version of this file compared `ImbalanceGateHook` with a persistent-storage variant on a mock PoolManager and reported a saving of about 35,600 gas. That setup didn't reflect real swap costs, and the persistent baseline wasn't a design anyone would deploy. The mock benchmark and the persistent variant have been removed.
