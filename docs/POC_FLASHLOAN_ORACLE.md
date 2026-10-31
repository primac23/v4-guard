# PoC: flash-loan manipulation of a spot-price lending market

## Setup

- Two Uniswap v4 pools with identical full-range liquidity (L = 1e18, price 1:1, 0.30% fee). One has no hook, the other has `TickExcursionGuardHook` with a bound of 50 ticks, roughly 0.5% of price.
- For each pool, a lending market (`VulnerableSpotLending`) that values token0 collateral at the pool's `slot0` price and lends token1 up to 80% LTV. Each market holds 10 token1.
- A flash lender holding 100 token1.

The market is naive on purpose. Reading `slot0` directly is a known anti-pattern, but it still shows up in production code, and it is the clearest way to show the attack.

## Attack, in one transaction

1. Flash-borrow 1 token1.
2. Swap all of it for token0 in the pool. The spot price of token0 jumps.
3. Deposit that token0 as collateral and borrow as much token1 as the inflated price allows.
4. Repay the flash loan and keep the rest. The collateral is left behind.

## Result

| | No hook | With TickExcursionGuardHook |
|---|---|---|
| Spot price after the swap (token1 per token0) | 3.9880 | swap reverted |
| Attacker profit on a 1 token1 loan | 0.5928 token1 | 0, the whole transaction reverts |
| Bad debt left in the market | 1.0936 token1 | 0 |

`testFuzz_WithGuard_AttackNeverProfitable` runs the same attack against the guarded pool with flash amounts from 0.000001 to 50 token1. Every run either reverts or ends at a loss for the attacker: within 50 ticks the price can only move about 0.5%, which is nowhere near enough to beat an 80% LTV.

## Reproduce

```bash
forge test --match-contract FlashLoanOracleManipulationPoC -vv
```

Source: `test/poc/FlashLoanOracleManipulation.t.sol`.

## What this shows, and what it doesn't

It shows that the hook removes the single-transaction version of this attack, whichever router the attacker uses. It does not turn `slot0` into a safe oracle. An attacker who can hold the price across several transactions or blocks is out of scope (see [THREAT_MODEL.md](THREAT_MODEL.md)). Lending markets should still use TWAPs or external oracles; the hook is a second line of defence for pools that end up being read this way anyway.
