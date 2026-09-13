# v4-guard — Threat Model

## 1. Purpose
v4-guard is a defensive security library for Uniswap v4 hooks. It provides two independent primitives:
1. TransientReentrancyGuard — transaction-scoped execution safety using EIP-1153 transient storage.
2. ImbalanceGateHook — transaction-scoped economic/accounting invariant enforcement based exclusively on BalanceDelta values observed during afterSwap.

The system is designed to enforce developer-defined invariants at an explicit settlement/finalization boundary. It is not intended to provide general-purpose protection against all forms of MEV, manipulation, malicious tokens, or economic attacks.

## 2. Security Boundary
Execution flow:
PoolManager.unlock() -> unlockCallback() -> swap() -> afterSwap() -> BalanceDelta -> TSTORE accumulator -> validateSettlementInvariant() -> ALLOW / REVERT.

## 3. Formal Model
For an atomic execution trace tau = {Delta_1, ..., Delta_n}, cumulative delta D(tau) = sum Delta_i:
ALLOW(tau) <=> |D_0(tau)| <= epsilon_0 and |D_1(tau)| <= epsilon_1
not ALLOW(tau) => REVERT(tau)

## 4. Protected Properties
* Transaction-scoped accounting: Accumulators reside in EIP-1153 transient storage.
* Final-state invariant enforcement: Evaluated at the finalization boundary.
* Fail-closed behavior: Any breach at settlement reverts.
* Revert isolation: Failed execution path restores transient state (T_after = T_before).
* Reentrancy protection: Direct and cross-function recursion blocked.

## 5. Explicit Non-Claims
v4-guard does not claim to prevent MEV, eliminate arbitrage, validate oracle correctness, or replace protocol audits.
