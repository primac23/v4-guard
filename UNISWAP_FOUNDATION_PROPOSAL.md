# Uniswap Foundation Grant Proposal: v4-guard

## Summary

- **Project:** v4-guard
- **Category:** Security infrastructure for hook developers
- **Requested:** $32,500 USDC
- **Duration:** 12 weeks, 4 milestones
- **Applicant:** Primac George ([github.com/primac23](https://github.com/primac23))

v4-guard is a small library of security hooks for Uniswap v4. Its core piece, `TickExcursionGuardHook`, caps how far a pool's price can move inside a single transaction. It runs on every swap, the router can't skip it, and on a single swap it adds 11,632 gas (7.8%).

## Problem

Pools are still used as price sources by lending markets, vaults and liquidation logic. The standard attack is a flash-loan round trip: move the price, exploit the consumer, move it back. Because the net flow is close to zero, checks based on volume or balances miss it. v4 makes it cheap to attach a check at the pool level, but today a hook developer who wants this has to write and audit it themselves.

## Current state (2026-10-31)

- `TickExcursionGuardHook` tested on the real v4 PoolManager: single-swap bound, cumulative excursion in one transaction, round-trip manipulation, bounded out-and-back arbitrage, and a 1,024-run fuzz of the bound.
- 27 tests passing.
- Gas, measured on identical pools with and without the hook:

| Swaps in one tx | No hook | With TickExcursionGuardHook | Overhead | Overhead per swap | Relative |
|:-:|-:|-:|-:|-:|-:|
| 1 | 149,285 | 160,917 | +11,632 | +11,632 | +7.8% |
| 2 | 228,883 | 248,261 | +19,378 | +9,689 | +8.5% |
| 5 | 404,603 | 447,353 | +42,750 | +8,550 | +10.6% |

- Working PoC: a flash-loan attack on a lending market that reads `slot0` earns 0.5928 token1 on a 1 token1 loan without the hook and reverts with it ([docs/POC_FLASHLOAN_ORACLE.md](docs/POC_FLASHLOAN_ORACLE.md)).
- Compared with the closest existing hook ([nirholas/circuit-breaker](https://github.com/nirholas/circuit-breaker)), which halts after a limit move but lets the breaching swap complete: with the same 50-tick bound, the same attack earns exactly what it earns on an unhooked pool (0.5928 token1) and reverts with v4-guard ([docs/COMPARISON_CIRCUIT_BREAKER.md](docs/COMPARISON_CIRCUIT_BREAKER.md)).
- Known limits are documented in the README and threat model.

An earlier version of this proposal cited a gas saving of about 35,600 measured against a persistent-storage variant on a mock PoolManager. That comparison wasn't representative and has been removed.

## Milestones

| Milestone | Deliverables | Acceptance criteria | Budget |
|---|---|---|---|
| **M1: Block-scoped mode and per-pool config** (weeks 1–3) | Optional block-scoped bound (manipulation split across transactions in one block). Per-pool deviation set at pool initialization. Stateful invariant tests on the real PoolManager. | Invariant suite with a handler covering swaps, liquidity changes and multiple pools; 1,024+ runs per target; all passing in CI. | $7,500 |
| **M2: Attack PoCs and symbolic checks** (weeks 4–6) | Further PoCs beyond the lending case (vault share pricing, liquidation triggers, multi-pool routes), each failing without the hook and reverting with it. Halmos checks of the excursion bound. | PoCs and symbolic checks run from one CLI command; results documented. | $8,000 |
| **M3: Independent review** (weeks 7–9) | Review by an independent security researcher, remediation, public report. | All High and Critical findings fixed; Medium findings fixed or accepted with written rationale. | $12,000 |
| **M4: Integration kit and release** (weeks 10–12) | Library form that can be inherited into existing hooks, deployment scripts with HookMiner, integration guide, tagged release. | Public release; at least 2 hook teams evaluate the integration and their feedback is published. | $5,000 |
| **Total** | | | **$32,500** |

## Out of scope

v4-guard is not an oracle, does not prevent MEV or arbitrage, and does not replace an audit of the protocols that consume pool prices.

## About me

I do independent smart contract security research on Immunefi, Cantina and HackerOne. I'm also building AEGIS ([github.com/primac23/aegis-core](https://github.com/primac23/aegis-core)), a fail-closed release authorization layer for cross-chain bridges with a Rust guardian daemon and live reorg and RPC-poisoning demos.
