# Web Market Trade (WMT)

WMT is an immutable ERC-20 that creates **1,000,000,000 tokens with 18 decimals** once, in its constructor. The immediate deployer receives the entire supply. The contract uses the unmodified OpenZeppelin Contracts v5.2.0 ERC-20 implementation.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract / source | `WMT` / `src/WMT.sol` |
| Token name | `Web Market Trade` |
| Symbol | `WMT` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor native value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Intended launch network | Ethereum, chain ID `1` |
| Compiler / EVM | Solidity `0.8.26` / Cancun |
| Optimizer / metadata hash | Enabled, 200 runs / `none` |

Deploy the creation bytecode for `src/WMT.sol:WMT` directly. The build artifact is `out/WMT.sol/WMT.json`. No initializer, linked libraries, external contracts, constructor configuration, RPC access, or subsequent settings are needed by the token. It also constructs successfully on an empty local chain.

For the IdentityMD launch, the factory is the immediate deployer and receives all tokens; the transaction origin and the requester receive no tokens from the constructor. The factory then performs the launch allocations. A direct EOA deployment instead assigns everything to that EOA. Deployment through any other contract requires that contract to be able to distribute its tokens.

## Behavior and assumptions

- Standard `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, and metadata functions. Successful mutations return `true`; invalid calls revert with OpenZeppelin ERC-6093 custom errors.
- Transfers deliver the exact amount. There are no taxes, transfer fees, rebases, wallet limits, trading gates, or account exemptions. Zero-value transfers between valid addresses and self-transfers are supported.
- Transfers to the zero address and approvals to a zero spender revert. No public mint or burn function exists, so `totalSupply()` remains fixed for the lifetime of the contract.
- Finite allowances decrease when spent. An allowance of `type(uint256).max` is treated as unlimited and does not decrease. `approve` replaces the previous allowance and accepts zero to revoke it. `transferFrom` requires allowance even when the spender is the holder.
- `Transfer` is emitted for minting and every transfer, including zero-value transfers. `Approval` is emitted for explicit approval changes; OpenZeppelin v5 does not emit it when an allowance is consumed by `transferFrom`. Integrations should query `allowance` for current values.
- There is no owner, administrator, pause, blacklist, seizure, upgrade, signature permit, or recovery mechanism. The deployer has the same transfer permissions as every other holder after construction.
- The contract makes no external calls, including during construction and transfers. Recipients need no callback interface. Native currency payments revert; forcibly delivered ETH or assets sent to the token contract cannot be recovered.

## Launch and operational responsibilities

The separate launch process writes `launch.json`, deploys the token, and configures the pool and distributor. This repository contains only the token and local tests; test harnesses are not application contracts to deploy. It does not broadcast transactions or require a private key.

The supplied launch policy allocates 10% (100,000,000 WMT) to the factory's MerkleDistributor, 88% (880,000,000 WMT) to pool seeding, and 2% (20,000,000 WMT) to the requester's specified remainder address. These are factory responsibilities; the constructor does not split the supply. The token imposes no restrictions on the subsequent transfers. The pair, pool fee, ticks, and opening price belong to the external launch configuration and are not token parameters.

Before release, the launch operator must verify the attested creation code, compiler settings, constructor arguments, exact supply and decimals, factory recipient, and launch allocation configuration. After deployment, verify the source and runtime bytecode on the target chain and confirm allocation receipts and pool operation. Independent adversarial review and the launch network's full protected tests remain part of release acceptance; local tests are not an audit.

### After launch

There are no owner settings, maintenance transactions, privileged keys, or upgrades for WMT. Holders manage their own custody and spender allowances. Approve only the amount a spender needs, revoke unused allowances, and account for the standard ERC-20 approval replacement race: a spender may use an existing allowance before a replacement confirms. Confirm a zero allowance before granting a replacement when needed. Mistaken transfers cannot be reversed by an administrator.

## Build and checks

With Foundry and Solidity 0.8.26 installed, all project dependencies are available locally:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xdb56978ba26e4ee0d46f4f6c8726ad12c0d03aa16638a1796e9b4379b8256f0e forge test
forge fmt --check
```

`foundry.toml` pins the compiler and disables the bytecode metadata hash. It grants no FFI or filesystem permissions. Tests use no environment reads or writes, forks, network requests, or filesystem reads. The seed above is supplied to the Foundry runner, not accessed by test code. Tests can run independently and in parallel. No deployment script or manifest is necessary to compile the deployable artifact.

The unit and fuzz tests cover supply and metadata, mint and transfer events, CREATE2 factory receipt, exact allocation and claim transfers, approvals, allowance exhaustion and revocation, zero and maximum values, self-transfers, unauthorized spending, atomic failure, rejection of administrative selectors, and runtime opcode restrictions. The launch transfer test uses local accounts for pool movements; it does not claim to execute Uniswap swaps. The supplied protected launch suite exercises the actual PoolManager separately.

The stateful invariant tests exercise four holders through transfers, finite/unlimited approvals, revocations, and delegated transfers, including insufficient-balance and insufficient-allowance failures. An independent model checks every balance and allowance after each action; invariants also check total supply and conservation of balances. Defaults are 1,000 runs per fuzz test and 256 sequences of 64 calls per invariant, with unexpected handler reverts treated as failures.

## Vendored dependencies

`lib/openzeppelin-contracts` contains the five required Solidity source files and MIT license from [OpenZeppelin Contracts v5.2.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.2.0). `lib/forge-std` contains the test library's complete `src` tree and its Apache/MIT licenses from [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7). They are ordinary files, not submodules, and require no install step. `DEPENDENCIES.json` records the source archive URLs, versions, archive hashes, and hashes of every vendored file. Third-party sources are unmodified.
