# Threat model

## Scope

This document covers `TickExcursionGuardHook`. `ImbalanceGateHook` is experimental; its limitations are listed in [INVARIANTS.md](INVARIANTS.md).

## Attacker

Any account or contract that can call `PoolManager.unlock()` and swap on a pool using the hook. The attacker has access to flash loans, uses their own router, controls the unlock callback entirely and can order swaps freely inside one transaction.

## What is protected

The integrity of the pool's spot price as seen by other contracts during a transaction. Typical consumers are lending markets, vaults and liquidation logic that read `slot0`.

## Defended

- A single swap that moves the price more than `MAX_TICK_DEVIATION` ticks.
- Several swaps in one transaction that add up to more than the bound.
- Round trips whose intermediate excursion exceeds the bound, even when the net flow is zero.
- Bypass through a custom router: the checks run in `beforeSwap`/`afterSwap`, which the PoolManager always calls for this hook.

## Not defended

- Manipulation spread across several transactions in the same block, or across blocks.
- Moves that stay within the bound. The bound has to be chosen per pool, based on liquidity and on how sensitive the price consumers are.
- Depth manipulation through adding or removing liquidity. The tick doesn't change, but price impact for the next trader does.
- Consumers that read a different pool, or the same pair on another venue.
- Large legitimate trades above the bound revert and have to be split across transactions. This is the intended trade-off.
- Batched settlement: every swap on a pool in one transaction counts against the same bound.

## Adversarial cases covered by tests

`test/Adversarial.t.sol`, on the real PoolManager:

- **Custom router.** An attacker-written router calls `unlock()` and `swap()` directly. A large swap is stopped, and the revert reason is checked to be `TickExcursionExceeded`, so it is the hook that stops it and not something else. A small swap through the same router is not blocked by the hook.
- **Several swaps in one `unlock()`.** A small swap followed by a large one in the same callback is stopped by the hook.
- **Direct calls to the callbacks.** Calling `beforeSwap` or `afterSwap` from anything other than the PoolManager reverts with `NotPoolManager`, so nobody can seed or skip the recorded start tick.
- **Non-zero start ticks.** Pools starting at price 2 (positive tick) and 1/2 (negative tick): the recorded start tick matches the real pre-swap tick exactly, and large moves revert. This checks the signed packing in transient storage.
- **Exact-output swaps.** Small ones pass, large ones revert.
- **Several pools in one transaction.** Two pools on the same hook have independent budgets; exceeding the bound on one of them reverts.
- **Caught reverts.** A large swap that reverts inside a try/catch leaves no transient state behind; the next swap records the real pre-transaction tick.

Not covered by tests: every possible router design (the guarantee relies on the PoolManager always calling the hook, which these tests exercise but cannot exhaust), manipulation across transactions, and formal verification.

## Assumptions

- The hook is deployed at an address whose flag bits match its permissions. The constructor checks this.
- `MAX_TICK_DEVIATION` is set at deployment. There is no owner, no admin function and no upgrade path.
- The chain supports EIP-1153 (Cancun or later).
