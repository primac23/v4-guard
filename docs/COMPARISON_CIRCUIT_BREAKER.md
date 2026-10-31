# Comparison: CircuitBreakerHook and a single-transaction oracle attack

[nirholas/circuit-breaker](https://github.com/nirholas/circuit-breaker) halts swapping after a limit move and, by design, lets the swap that crosses the limit complete. This file records what that means for the attack in [POC_FLASHLOAN_ORACLE.md](POC_FLASHLOAN_ORACLE.md).

## Setup

Same as our PoC: full-range pool (L = 1e18, price 1:1, 0.30% fee), a lending market that prices collateral from `slot0` at 80% LTV, and a 1 token1 flash loan. `CircuitBreakerHook` is configured with `maxTickMove = 50`, the same bound as our hook, plus `windowSeconds = 300` and `cooldownSeconds = 3600`. The test runs inside the circuit-breaker repository at commit `5371347`, with that repository's own dependencies.

## Result

| | No hook | CircuitBreakerHook | TickExcursionGuardHook |
|---|---|---|---|
| Attack outcome | succeeds | succeeds | reverts |
| Attacker profit on a 1 token1 loan | 0.5928 token1 | 0.5928 token1 | 0 |
| Bad debt left in the market | 1.0936 token1 | 1.0936 token1 | 0 |
| Pool afterwards | unchanged | halted for one hour, honest swaps revert | unchanged, trading continues |

With CircuitBreakerHook the attacker's profit and the market's bad debt are identical, to the wei, to the pool with no hook at all.

## Why

The swap that crosses the limit completes, so the lending market reads the inflated price inside the same transaction. The halt starts only after that. The attacker never needs to swap back, so blocking later swaps doesn't affect them, while honest traders are locked out for the cooldown.

## Fairness note

This is not a bug in CircuitBreakerHook. It targets a different problem: buying time during a sustained or erroneous move without capping the price, and its author argues that a price cap is the worse tool for that goal. The two hooks answer different threats. Since a pool can only have one hook, a pool that needs both behaviours would need a hook that combines them.

## Reproduce

Clone github.com/nirholas/circuit-breaker with submodules, check out commit `5371347`, copy `docs/comparison/CircuitBreakerComparison.t.sol` from this repository to `test/V4GuardComparison.t.sol` there, and run:

    forge test --match-contract CircuitBreakerVsSingleTxAttack -vv
