# v4-guard — Empirical Gas Benchmarks

## 1. Methodology
Measured in Foundry (Solc 0.8.26, Cancun EVM, Optimizer 10,000 runs) comparing Baseline, v4-guard Transient, and Persistent Storage implementations.

## 2. Benchmark Results
| Swaps (n) | Baseline | v4-guard Transient | Persistent | Guard Overhead | Gas Saved vs Persistent | Efficiency Gain |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | 53,671 | 58,934 | 94,599 | +5,263 | 35,665 | 37.7% |
| 2 | 53,743 | 62,857 | 98,816 | +9,114 | 35,959 | 36.4% |
| 5 | 53,956 | 74,624 | 111,464 | +20,668 | 36,840 | 33.0% |
| 10 | 54,312 | 95,602 | 132,545 | +41,290 | 36,943 | 27.9% |
| 20 | 55,024 | 144,636 | 174,708 | +89,612 | 30,072 | 17.2% |

## 3. Analysis
* Avoided persistent initialization cost: ~35,600 gas per transaction.
* Marginal accounting cost: ~4,100 gas / swap.
* Settlement validation cost: <1,200 gas with zero storage cleanup required.
