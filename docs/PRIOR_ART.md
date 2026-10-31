# Prior art, and how each comparison was established

This file exists so that claims about other projects can be checked. Every entry says how we know what we say about it.

## Evidence levels

- **Tested**: we ran the project's code against our PoC.
- **Source read**: we read the contract, but did not run it against our PoC.
- **Docs read**: we only read its README, documentation or blog post.

## Search

Done on 2026-10-31: GitHub, the Uniswap blog and developer docs, OpenZeppelin's uniswap-hooks documentation and audit reports, the awesome-uniswap-hooks lists and Uniswap's hooklist registry. This is not exhaustive. Unpublished or private work, and hooks deployed without public source, are not covered.

## Projects

| Project | Mechanism | What it acts on | Scope | Evidence | Relation to v4-guard |
|---|---|---|---|---|---|
| [nirholas/circuit-breaker](https://github.com/nirholas/circuit-breaker) | Reference tick per time window; after a swap crosses the limit, swapping halts for a cooldown. The breaching swap completes, by design. | Swaps after the breach | Per window, across transactions | **Tested** at commit `5371347`, source read | Our single-transaction PoC succeeds there with the same profit as on an unhooked pool. It covers multi-transaction moves, which v4-guard does not. |
| [FairOpenHook](https://github.com/n0krayy/FairOpenHook) | Reverts swaps that move the price more than 25% from a rolling reference during the first 100 blocks | The swap itself | Launch window only | Docs read | Similar revert-based approach, aimed at token launches. Not tested against our PoC. |
| [CrossPoolOracleHook](https://github.com/pnupu/crosspooloraclehook) | Compares a swap's price impact with movements in deep reference pools; blocks impact the references don't explain | The swap itself | Needs reference pools | Docs read | Different detection method. Not tested against our PoC. |
| [Uniswap Truncated Oracle](https://blog.uniswap.org/uniswap-v4-truncated-oracle-hook) | Caps how far the recorded oracle tick moves per block | The oracle record, not swaps | Per block | Docs read | Protects consumers that read its oracle. Consumers that read `slot0` are not affected by it. |
| [OpenZeppelin AntiSandwichHook](https://docs.openzeppelin.com/uniswap-hooks) | Beginning-of-block checkpoint; no swap fills at a better price than the block started with | Swap execution price | Per block | Docs and audit report read | Built against sandwiching. Its effect on our PoC was not tested. |

## What we claim, and what we don't

We claim, with a reproducible test, that our single-transaction PoC succeeds against circuit-breaker with the same 50-tick bound and reverts against v4-guard.

We do not claim:

- that v4-guard is the only hook with this behaviour;
- anything about how FairOpenHook, CrossPoolOracleHook or AntiSandwichHook handle our PoC;
- that v4-guard is better in general. The hooks above address different threats, and several cover cases v4-guard does not.

Open work: run the PoC against FairOpenHook, CrossPoolOracleHook and AntiSandwichHook, and move them to "Tested" or record why they don't apply.
