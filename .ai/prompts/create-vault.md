You are DeFi and EVM blockchain expert.

I want to create ERC4626 vault.

Requirements:
- the vault should follow all ERC4626 functionalities
- deposit and withdaw function should work
- everything should be secure and follow the best software engineering practice.
- the provides liquidity to the Dragon Swap pool
- Dragon Swap is a fork of Uniswap V3 (concentrated liquidity)
- the vault has functions:
  - createPosition
  - modifyPosision
  - collectRewards
  - swapTokens

The problem which the vault should solve:
We want to use that vault to automate providing liquidity to the Dragon Swap pools (concentrated liquidity). The vault is a single liquidity provider which represents all the vault depositors and perform on behalf of depositors. Vault manager is an entity that triggers transactions to modify LP position to keep vault profiting by keeping the position always in the range.

Read Dragon Swap documentation in `dragon-swap-docs`:
<dragon-swap-docs>
https://docs.dragonswap.app/dragonswap/guides/liqudity-providers/v2-concentrated-liquidity-pools
https://docs.dragonswap.app/dragonswap/faq/contract-addresses/dragonswapv2
https://docs.dragonswap.app/dragonswap/resources/developer-resources/smart-contracts/dragonswapv2
</dragon-swap-docs>

In `resources-code` the are examples of the code to realize these features.
It comes from IPOR Fusion defi protocols which follow best proctices.

<resources-code>
This is how you can deal with creating a position:
https://github.com/IPOR-Labs/ipor-fusion/blob/3b3cd9b2a44a1bec0482213e289af64780389c32/contracts/fuses/uniswap/UniswapV3NewPositionFuse.sol

This is how you can deal with modifying a position:
https://github.com/IPOR-Labs/ipor-fusion/blob/a10866147fa2ebebadadc4a08aeed19eb785548b/contracts/fuses/uniswap/UniswapV3ModifyPositionFuse.sol

This is how you can deal with collecting rewards:
https://github.com/IPOR-Labs/ipor-fusion/blob/a10866147fa2ebebadadc4a08aeed19eb785548b/contracts/fuses/uniswap/UniswapV3CollectFuse.sol
</resources-code>

Before you provide a solution ask me questions I can answer. 
Repeat that process until you get enough information about my intention.
Then provide a report with all decisions I made, crucial aspects and your considerations on my task.
Ask me to confirm everyting is right.
Then implement a solution.

---

Network and addresses
- that's SEI mainnet, chainId 1329
- take it from docs

Vault asset and pool:
- token1
- pool address: 0xe62fd4661c85e126744cc335e9bca8ae3d5d19d1
- token0 address: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c
- token1 address: 0xe15fC38F6D8c56aF07bbCBe3BAf5708A2Bf42392
- fee tier is 0.3
- for deposit and withdraw operations it is always a single asset. For operations, the vault manager should call swap function manually that during providing liquidity we already have both tokens.

Position strategy
- single
- percentage around mid price
- manual only
- spot

Swaps
- single-hop only through the pool
- required params as recommended
- only owner
- fix my typo
- all internal operations are manager-only

Economics and fees
- no fees, no caps

Accounting and valuation
- TWAP period
- hold fees as idle assets until manager acts
- no rescue function

Implementation preferences
- OpenZeppelin ERC4626 base (non-upgradeable) 
- name and symbol
- tests: yes, test these features
- permit not required

Docs and integration
- Dragon Swap router/position manager APIs
- no more features from IPOR Fusion

More context:
- this is POC for hackathon project

---

### Decisions captured

- **Network**
  - **Chain**: SEI mainnet, chainId 1329
  - **Addresses**: Use DragonSwap’s NonfungiblePositionManager, SwapRouter, Factory, Quoter from docs; pass as constructor params and pin pool at `0xe62f...d19d1`.

- **Vault basics**
  - **Standard**: OpenZeppelin ERC4626, non-upgradeable
  - **Asset**: token1 `0xe15f...2392`
  - **Pool**: token0 `0x0555...2B9c`, token1 `0xe15f...2392`, fee tier 0.3% (assumed 3000)
  - **Single position**: One NFT tracked in the vault

- **Ops and roles**
  - **Manager model**: Manager triggers position lifecycle; separate `manager` role, settable by owner
  - **Access**
    - `createPosition`, `modifyPosition`, `collectRewards`: manager-only
    - `swapTokens`: owner-only
  - **Manual strategy**: Manager adjusts ticks manually; range sized as a percentage around spot

- **Swaps**
  - **Single-hop** via pool using router
  - **Params**: exactIn/exactOut, minOut/maxIn, deadline, direction (token0↔token1)

- **Economics**
  - No management/performance/deposit/withdrawal fees, no caps

- **Accounting**
  - `totalAssets`: idle balances + position amounts valued in token1 using pool TWAP
  - Collected fees stay idle until manager acts

- **Security**
  - Reentrancy guard, input/role validation, deadline/slippage checks, minimal approvals
  - No rescue function

- **Tests**
  - Unit tests for ERC4626 flows, access control, and wiring
  - Note: full e2e against DragonSwap on SEI won’t run locally; tests will focus on ERC4626 correctness and role gating

### Open confirmations needed

- **Vault token metadata**: Provide `name` and `symbol` for ERC4626 shares.
- **TWAP period**: How many seconds? (propose 300s default)
- **Range width**: What percentage around spot to set ticks? (e.g., ±5%, ±10%)
- **Withdraw behavior if short on token1**:
  - Should withdraw/redeem be allowed to internally decrease liquidity and swap token0→token1 to fulfill redemptions? This conflicts with “swapTokens owner-only”.
  - Options:
    - A) Withdraws can perform internal swaps as part of fulfilling user requests (recommended for ERC4626 UX).
    - B) Withdraws only use available token1 (idle + token1 share from decreasing liquidity); if insufficient, revert and require manager to pre-balance via `swapTokens`.
- **Fee tier encoding**: Confirm Uniswap-style fee = 3000 for 0.3%.

Once you confirm these, I’ll implement the vault, deployment, and tests accordingly.

---

Vault token metadata:
- name: DragonSwap USDC DEX LP
- symbol: DRGusdc

TWAP period:
- 300s

Range width:
- ±10%

Withdraw behavior if short on token1:
- option A

Fee tier encoding:
- yes

---

Confirm:
- Manager address to set at deploy time?
- DragonSwap SEI mainnet addresses for `PositionManager`, `SwapRouter`, `Factory`, `Quoter` from docs: should I hardcode in the deploy script or pass via env?

- I’ll use fee=3000, TWAP=300s, ±10% ticks, name `DragonSwap USDC DEX LP`, symbol `DRGusdc`.

- Summary of decisions and impact:
  - Single-asset ERC4626 with `asset=token1`. Deposits/withdraws in token1 only.
  - `withdraw/redeem` auto-frees liquidity and swaps token0→token1 if needed (Option A).
  - Manager-only `createPosition`, `modifyPositionIncrease/Decrease`, `collectRewards`. Owner-only `swapTokensExactIn`.
  - `totalAssets` accounts for idle tokens + estimated amounts in the single position valued via 300s TWAP to token1.

If that’s correct, I’ll:
- Add deploy script for SEI 1329 with DragonSwap addresses from docs.
- Write unit tests for deposit/withdraw, access control, and position ops stubs.

---

- Manager address: yes
- hardcode addresses
- yes
- Summary of decisions and impact:
  - yes
  - yes
  - yes
  - yes

---

Do you want me to:
- Plug your manager address now and run the deploy, or leave it for you?
- Proceed to write unit tests for deposit/withdraw and role gating?

- Deployment script hardcodes:
  - PositionManager: 0xa7FDcBe645d6b2B98639EbacbC347e2B575f6F70
  - SwapRouter02: 0x11DA6463D6Cb5a03411Dbf5ab6f6bc3997Ac7428
  - QuoterV2: 0x38F759cf0Af1D0dcAEd723a3967A3B658738eDe9
  - Factory: 0x179D9a5592Bc77050796F7be28058c51cA575df4

Summary:
- Contract and deploy script are in place per your specs; ready to test and deploy on SEI.

---

Proceed to write unit tests for deposit/withdraw and role gating

---

Summary:
- Created mocks: `MockERC20`, `PoolMock`, `PositionManagerMock`, `RouterMock`.
- Wrote `packages/hardhat/test/DragonSwapLpProviderVault.ts` covering:
  - ERC4626 metadata and deposit/withdraw.
  - Role gating: manager-only lifecycle, owner-only swap.
- Deployment script `01_deploy_dragonswap_vault.ts` is ready with SEI hardcoded addresses.
- Contract compiles and tests pass.

Do you want me to run a deployment with your `VAULT_MANAGER`/`VAULT_OWNER` now, or proceed to wire a minimal NextJS debug page for the vault interactions?

---

Run a deployment