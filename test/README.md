# DCA test coverage

The suite deploys the real `src/DCAToken.sol` with the existing vendored dependencies.
The expected supply is independently fixed at `1_000_000_000 * 10 ** 18`.
No fork, RPC, environment variables, storage edits, or synthetic token minting are needed.

| File | Coverage |
| --- | --- |
| `DCAToken.t.sol` | Existing constructor, metadata, factory mint recipient, events, transfers, approvals, revert paths, forbidden entry points, and fuzz tests. |
| `DCAToken.adversarial.t.sol` | One-unit and maximum-integer boundaries; largest finite versus unlimited approvals; approval exhaustion and refunding; caller and spender isolation; failure rollback; zero-value operations; round-trip and split-spending properties. |
| `DCAToken.invariant.t.sol` | Random sequences across four holders, conservation, independent balance and allowance accounting, stable metadata, and full-balance transfer liveness after every sequence. |
| `LaunchTransfers.t.sol` | Existing exact token delivery through factory distribution, claims, and transfers between a pool account and a trader. |

The invariant campaign explicitly targets ten handler actions. Valid operations mix with
insufficient-balance, insufficient-allowance, zero-recipient, zero-spender, and revoked-approval
attempts. Rejection checks require the exact custom error, including its arguments. Failed
calls leave the expected ledger unchanged; all four balances and all sixteen allowance pairs
are compared after every action. Zero-address balances and allowances are checked separately.
The full-balance action always selects a funded holder and a distinct recipient, guaranteeing
nonzero movement whenever selected. A deterministic sequence also covers nonzero delegated
spending, failed operations, and subsequent successful spending.

Inline settings run each new fuzz property 1,000 times and the invariants for 256 sequences
of depth 128, with unexpected handler reverts treated as failures. The original fuzz tests
retain their existing settings. The end-of-sequence check transfers each holder's whole
balance out and back, checks both legs exactly, and rechecks the balance and allowance ledger.

Run `forge build` and `forge test`. Local validation also passed offline with artifacts and
cache redirected into disposable scratch space:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Result: 52 reported tests passed, none failed or skipped. Foundry groups the three invariant
properties into one reported campaign: 32,768 handler calls, all ten actions exercised, no
unexpected reverts or discarded calls. No confirmed implementation defect was found.

The supplied protected launch harness additionally requires Uniswap v4 and launch-system
contracts and manifest inputs that are outside this repository. These local tests validate
the token's behavior; they do not claim to execute full pool initialization or swaps.
