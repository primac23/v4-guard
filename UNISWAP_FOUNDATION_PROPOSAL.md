# Uniswap Foundation Grant Proposal: v4-guard

## 1. Project Summary
* **Project Name:** v4-guard
* **Category:** Security Infrastructure / Developer Tooling
* **Target:** Uniswap v4 Hook Ecosystem
* **Requested Funding:** $32,500 USDC
* **Duration:** 12 Weeks (4 Milestones)

v4-guard provides reusable, auditable defensive security primitives for Uniswap v4 hooks leveraging EIP-1153 transient storage:
1. `TransientReentrancyGuard` — zero-SSTORE execution safety lock.
2. `ImbalanceGateHook` — transaction-level accounting invariant enforcement based exclusively on observed `BalanceDelta` values at an explicit finalization boundary.

---

## 2. Milestones & Budget Allocation

| Milestone | Deliverables | Target KPI | Allocation |
|---|---|---|---|
| **M1: Core Hardening & Invariant Fuzzing** (Weeks 1–3) | Slot domain separation across pools/managers; fee-on-transfer edge-case docs; expanded invariant harness. | All documented security invariants covered by deterministic tests and stateful fuzzing (1,024+ runs per target). Zero persistent storage allocation. | $7,500 USDC |
| **M2: Adversarial Testing & Formal Specs** (Weeks 4–6) | Formal verification models (Halmos / symbolic execution) demonstrating $D(\tau) \le \epsilon$ and EIP-1153 rollback isolation. | Mathematical proof / symbolic check reproducible from CLI; zero slot-aliasing risks identified. | $10,000 USDC |
| **M3: Independent Security Review** (Weeks 7–9) | External third-party audit engagement; remediation of all findings; public report publication. | All High/Critical findings remediated; Medium findings either remediated or explicitly accepted with documented rationale. | $10,000 USDC |
| **M4: Developer Tooling & Release** (Weeks 10–12) | Public GitHub release, plug-and-play template harness, integration guide, npm distribution. | Public release; reproducible test harness; at least 2 ecosystem pilot integrations evaluated. | $5,000 USDC |
| **TOTAL** | | | **$32,500 USDC** |

---

## 3. Current Verification Status
* **Test Results:** 16 passed, 0 failed, 0 skipped (Foundry, Solc 0.8.26, Cancun EVM).
* **Fuzz Targets:** 1,024 runs for lock clearing and settlement invariants.
* **Empirical Benchmarks:** ~35.6k gas saved vs persistent storage; ~4.1k marginal gas per guarded swap.
