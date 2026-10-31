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

## Assumptions

- The hook is deployed at an address whose flag bits match its permissions. The constructor checks this.
- `MAX_TICK_DEVIATION` is set at deployment. There is no owner, no admin function and no upgrade path.
- The chain supports EIP-1153 (Cancun or later).
