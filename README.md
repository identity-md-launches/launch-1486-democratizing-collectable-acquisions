# Democratizing Collectable Acquisions (DCA)

A fixed-supply ERC-20 implemented in [`src/DCAToken.sol`](src/DCAToken.sol), using the
vendored OpenZeppelin Contracts v5.4.0 ERC-20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract | `DCAToken` |
| Token name | `Democratizing Collectable Acquisions` |
| Symbol | `DCA` |
| Decimals | `18` |
| Supply | `1,000,000,000 DCA` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor payment | None; the constructor is nonpayable |
| Initial recipient | The immediate deploying account, `msg.sender` |
| Target launch chain | Ethereum, chain ID `1` |

The name preserves the requested spelling, **Acquisions**. The constructor mints
the entire supply once and emits the standard `Transfer` event from the zero
address. Supply and metadata cannot subsequently be changed.

## Behavior and assumptions

- Transfers deliver the exact requested amount. There are no taxes, fees,
  rebases, transfer limits, vesting rules, or address exemptions.
- There are no owner, administrator, mint, burn, pause, blacklist, seizure,
  upgrade, or initialization functions. The deployer has the same runtime rights
  as every other holder.
- `transfer`, `approve`, and `transferFrom` return `true` on success. Invalid
  operations revert with the vendored OpenZeppelin ERC-20 custom errors; failed
  operations leave balances and allowances unchanged.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`,
  as required by [ERC-20](https://eips.ethereum.org/EIPS/eip-20). Self-transfers
  preserve balances but still require sufficient funds. Transfers to the zero
  address revert, including transfers of zero tokens.
- `approve` replaces the spender's allowance and emits `Approval`. An allowance
  of `type(uint256).max` is treated as unlimited and is not reduced by spending.
  Other allowances decrease with `transferFrom`; spending does not emit an
  additional `Approval` event in this OpenZeppelin version.
- There are no external calls, token receiver callbacks, oracle dependencies,
  signatures, scheduled actions, or liquidity-management functions in the token.
  There is no native-currency deposit or asset-recovery function.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
sha256sum --check DEPENDENCIES.sha256
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM target, optimization with
200 runs, and `bytecode_hash = "none"`. FFI is disabled and filesystem permissions
are empty. All Solidity dependencies are ordinary files in `lib/`; there are no
submodules, package installation steps, RPC requirements, or test environment
variables. With the pinned compiler already installed, the project builds and
tests offline. No compiler binary is included.

The test suite includes:

- Metadata, exact initial supply, a single mint event, and factory deployment
  through CREATE2 with callers distinct from the factory.
- Exact transfers, zero and self-transfers, approvals and revocation, finite and
  unlimited allowances, and standard events.
- Failure cases for insufficient balances or allowances, unauthorized spending,
  zero recipients, and atomic rollback of failed delegated transfers.
- Attempts to mint, burn, upgrade, freeze, seize, or otherwise administer the
  token from both the deployer and a stranger; native-currency and unknown calls
  also fail.
- Runtime size and an instruction-aware scan for `DELEGATECALL`, `CALLCODE`, and
  `SELFDESTRUCT`, matching the supplied protected check's method.
- Four fuzz tests, each configured for 512 cases, and two stateful invariant
  properties over four holders. The invariant handler exercises transfers,
  approvals, revocation, and delegated transfers across 128 runs of depth 64,
  comparing balances and allowances with an independent accounting model.
- The token transfers used in launch distribution, distributor claims, and
  transfers between a pool account and an ordinary trader.

`test/LaunchTransfers.t.sol` checks the token side of launch flows. Full Uniswap
v4 pool initialization, liquidity seeding, pricing, and swaps are exercised by
the separate launch verifier's protected harness, which requires infrastructure
and launch configuration outside this project.

Local validation used Foundry 1.8.3 and Solidity 0.8.26: `forge build`,
`forge test` (35 reported tests, zero failures or skips), and `forge fmt --check`
passed. A clean copy containing only delivered sources, dependencies, and
configuration also passed an offline build and test run with an empty environment
and four test threads. All 36 vendored file checksums matched. Slither and Mythril
were not run.

## Deployment and operational responsibilities

The deployment artifact is `out/DCAToken.sol/DCAToken.json`, built from
`src/DCAToken.sol:DCAToken`. Deploy its creation bytecode with an empty constructor
argument list. The constructor neither calls another contract nor needs any
pre-existing chain state. There are no linked libraries or application contracts
to deploy first.

For the specified launch, the factory must be the immediate deploying account:
it receives all `10^27` units. An EOA deploying directly would instead receive
the entire supply. A deployment wrapper would receive it itself; `tx.origin`
does not receive a special allocation. The factory deployment test checks this
distinction. Deployment is direct and immutable, without a proxy.

Distribution and liquidity are the launch system's responsibility. The supplied
launch policy assigns 10% to its MerkleDistributor, 75% to pool seeding, and the
remaining 15% to the supplied remainder recipient. The token imposes no special
transfer rules on any of these participants. The separate manifest step records
the supplied pool and economics parameters; this repository contains no
`launch.json`. The token itself does not know or require a factory, distributor,
pool manager, paired-token, or recipient address as configuration.

### After launch

There are no token settings to initialize or owner-only setters to call. The
launch operator is responsible for verifying the deployed artifact and metadata,
confirming the initial mint and launch distributions, and publishing the verified
source and token address. Holders control their balances and approvals. Frontends
should display 18 decimals, prefer bounded allowances, and let users revoke an
existing allowance before replacing it; pending spending transactions can race
approval changes.

The initial recipient controls the whole supply until distribution. No operator
can recover lost holder keys, reverse transfers, or rescue assets sent to the
token contract. Integrators should only send tokens to contracts that can manage
them. Independent security review and the protected launch integration checks
remain release responsibilities. This work performs local deployment simulations
and tests; no live transactions are broadcast.

## Dependency provenance

OpenZeppelin's `ERC20`, its four supporting Solidity source files, and its MIT
license are vendored unchanged from
[v5.4.0, commit `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0`](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/c64a1edb67b6e3f4a15cca8909c9482ad33a02b0).
The Foundry test library's Solidity sources and MIT/Apache-2.0 licenses are
vendored unchanged from
[forge-std v1.9.7, commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505`](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505).
forge-std is used only by tests.

[`DEPENDENCIES.json`](DEPENDENCIES.json) records the exact upstream commits and
archive hashes. [`DEPENDENCIES.sha256`](DEPENDENCIES.sha256) records the digest of
every vendored file. Build and test commands never download dependencies.
