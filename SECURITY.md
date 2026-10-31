# Security policy

## Status

v4-guard is not audited. The test suite, including the adversarial cases in `test/Adversarial.t.sol`, shows how the code behaves in the situations it covers. It is not a security certification. Don't rely on it in production before an independent review.

The reference version for reviews is the `v0.2.0` tag.

## Scope

In scope:

- `src/TickExcursionGuard.sol`
- `src/TickExcursionGuardHook.sol`

Out of scope:

- `src/ImbalanceGateHook.sol`: experimental, and documented as bypassable because its check depends on the router.
- `src/TransientReentrancyGuard.sol`: small utility, not part of the guard.
- Tests, scripts and documentation.

## What counts as breaking the guard

- A swap that completes while leaving a pool's tick more than `MAX_TICK_DEVIATION` away from that pool's tick before its first swap in the same transaction.
- Any way to seed, reset or skip the recorded start tick within a transaction.
- Interference between pools that share the hook.
- A way to make ordinary swaps revert beyond the trade-offs listed below.

## Known and accepted

These are documented limits, not findings:

- Manipulation spread across several transactions or blocks.
- Price moves that stay within the bound.
- The gas overhead per swap.
- All swaps on a pool in one transaction sharing one budget, including in batched settlement.

## Reporting

Please use GitHub's private reporting: the Security tab of this repository, then "Report a vulnerability". A Foundry test that reproduces the issue helps a lot. I aim to reply within a week.
