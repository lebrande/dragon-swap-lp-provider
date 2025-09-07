### For Dragon Swap bounty

- We built a liquidity vault that users can deposit into to gain automated LP exposure across DragonSwap UniV3 pools. The vault optimizes placement, rebalances positions, harvests fees, and manages risk so depositors get passive, diversified exposure without manual operations.
- Strategy highlights:
  - Concentrated-liquidity management for UniV3 using volatility-aware ranges and threshold-based re-centering; passive ratio management for UniV2 with rebalancing.
  - Single-sided deposits/withdrawals with internal zaps to the correct token mix.
- Technical notes:
  - Core contract: `packages/hardhat/contracts/DragonSwapLpProviderVault.sol`
  - Tested with Hardhat unit and fork tests; interacted via Scaffold-ETH debug UI for quick validation.

## For Scaffold-ETH bounty

- We mostly used Hardhat tests to drive development. Tests are the core and main part of the implementation, covering deposits/withdrawals, fee harvesting, rebalancing logic, tests on Sei chain fork.
- We leveraged the Scaffold-ETH 2 stack for fast iteration: `yarn test` + `yarn deploy`, using the built-in debug UI to call contract functions and validate behavior alongside our test suite.

## For ETH Warsaw bounty

- Value proposition: One-click, automated liquidity provisioning on DragonSwap that reduces operational complexity, improves capital efficiency (especially in UniV3), and transparently manages fees and risk for depositors.
- Target group: Individual LPs, DAO treasuries, token teams seeking sustained liquidity, and strategy curators who want to plug in differentiated LP algorithms.
- Revenue streams: Configurable protocol fees (e.g., small management fee on TVL, and/or performance fee on realized trading fees), optional keeper rebates, and potential white-label vaults for token projects.
- Costs: automation gas, audits/security reviews, monitoring/infra, and ongoing strategy research and tuning.
- Business Model Canvas (abridged):
  - Key partners: DragonSwap, RPC/infra providers, keeper networks.
  - Key activities: Strategy research, on-chain integrations, monitoring and risk management.
  - Key resources: Smart contracts, backtesting models, operational runbooks.
  - Customer relationships: Non-custodial, transparent on-chain accounting and operations, clear docs.
  - Channels: DragonSwap ecosystem.
  - Customer segments: asset managers, market makers, LPs, DAOs, token issuers, advanced DeFi users.
  - Cost structure: Development, audits, infra, keeper ops.
  - Revenue: Protocol fees and white-label arrangements.


