# Invariants

## 1. TickExcursionGuardHook

For a pool P and a transaction T, let `t0` be the tick of P right before the first swap on P in T, and `t_k` the tick after the k-th swap on P in T.

Checked in `afterSwap`, for every k:

    |t_k - t0| <= MAX_TICK_DEVIATION

- It holds after every swap, not only at the end of the transaction. A round trip that goes out of bounds and comes back reverts at the first swap that crosses the bound.
- It doesn't depend on the router: both checks run in hook callbacks invoked by the PoolManager.
- `t0` lives in transient storage keyed by pool id. Pools don't share state, and the value is gone at the end of the transaction.
- If a swap reverts, its transient write reverts with it.

Covered by `test/TickExcursionGuardHook.t.sol`: deterministic cases (single large swap, cumulative excursion, round-trip manipulation, bounded out-and-back) plus a 1,024-run fuzz on swap size and direction.

## 2. TransientReentrancyGuard

The lock is 0 or 1 in a fixed transient slot. Entry reverts with `ReentrantCall()` if the lock is 1, otherwise sets it. Exit clears it. It is also cleared automatically at the end of the transaction.

## 3. ImbalanceGateHook (experimental)

For swaps on pool P within a transaction, `D = sum of BalanceDelta`. `validateSettlementInvariant(P)` reverts if `|D0| > e0` or `|D1| > e1`.

Limitations:

- `validateSettlementInvariant` is not called by the PoolManager. It runs only if the router calls it, so anyone using their own router skips it.
- A round trip with near-zero net flow passes, however large the intermediate swaps are.
- The accumulator lasts for the whole transaction, so two `unlock()` calls in one transaction share it.

Treat it as a volume limit for trusted routers, not as protection against an attacker.
