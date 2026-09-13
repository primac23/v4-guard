# v4-guard

**Defensive Security Primitives & Transaction-Level Invariant Enforcement for Uniswap v4 Hooks**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Foundry](https://img.shields.io/badge/Foundry-passing-brightgreen.svg)](https://getfoundry.sh/)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue.svg)](https://soliditylang.org/)
[![EVM](https://img.shields.io/badge/EVM-Cancun-orange.svg)](https://eips.ethereum.org/EIPS/eip-1153)

## Overview
v4-guard provides reusable security building blocks for Uniswap v4 hook developers using EIP-1153 Transient Storage:
1. TransientReentrancyGuard - zero-SSTORE execution safety lock.
2. ImbalanceGateHook - transaction-level accounting invariant checking based on BalanceDelta.

## Testing
Run test suite:
forge test -vvv

Run gas benchmarks:
forge test --match-contract GasBenchmarkTest -vv

## Documentation
- docs/THREAT_MODEL.md
- docs/BENCHMARKS.md

## License
MIT
