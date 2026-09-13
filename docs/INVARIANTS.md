# v4-guard — Invariant Specifications

## 1. Execution Safety Invariant (TransientReentrancyGuard)
For any protected hook entry point $f \in \mathcal{F}_{\text{protected}}$:

$$\text{LockState}(t) \in \{0, 1\}$$

* **Entry:** If $\text{LockState}(t) = 1$, execution reverts with `ReentrantCall()`. Otherwise, $\text{LockState}(t) \leftarrow 1$.
* **Exit:** $\text{LockState}(t) \leftarrow 0$.
* **Lifecycle:** Stored exclusively in EIP-1153 transient storage on a deterministic slot. Automatically clears at transaction termination.

---

## 2. Economic Settlement Invariant (ImbalanceGateHook)
For an atomic execution trace $\tau = \{\Delta_1, \Delta_2, \ldots, \Delta_n\}$ observed across $n$ swap callbacks within a single `PoolManager.unlock()` execution context:

$$\Delta_i = \text{BalanceDelta}_i = (\delta_{0,i}, \delta_{1,i})$$

Cumulative observed trace delta:
$$D(\tau) = \sum_{i=1}^{n} \Delta_i = \left(\sum_{i=1}^{n} \delta_{0,i}, \; \sum_{i=1}^{n} \delta_{1,i}\right) = (D_0(\tau), D_1(\tau))$$

Configured bound parameter: $\epsilon = (\epsilon_0, \epsilon_1)$

### Settlement Rule (Evaluated at Finalization Boundary)
$$\text{Settlement}(\tau) = \text{ALLOW} \iff |D_0(\tau)| \le \epsilon_0 \land |D_1(\tau)| \le \epsilon_1$$
$$\neg \text{ALLOW}(\tau) \implies \text{REVERT}(\tau)$$

Intermediate deviations where an individual step $k$ exhibits $|\sum_{i=1}^k \delta_{j,i}| > \epsilon_j$ are permissible if and only if subsequent compensating actions satisfy the bound prior to settlement finalization.

---

## 3. Failure Isolation & Rollback Guarantee
For any nested execution frame $\tau_{\text{inner}}$:

$$\tau_{\text{inner}} \to \text{REVERT} \implies T_{\text{after}} = T_{\text{before}}$$

Transient storage modifications revert alongside EVM state reversals, guaranteeing zero residual accounting pollution for subsequent independent operations within the block.
