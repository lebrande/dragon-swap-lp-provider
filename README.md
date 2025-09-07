# Dratewka Vaults

## DragonSwap LP Provider Vault

Brief: Automated LP provisioning vault for DragonSwap Sei chain. It streamlines adding/removing concentrated liquidity and managing positions via a single, gas-efficient vault, with a simple Next.js UI for local testing and demos.

### Built with
- 🏗 Scaffold-ETH 2 (Next.js App Router, Wagmi, RainbowKit, Hardhat, Typescript)
- Contracts live in `packages/hardhat`; UI in `packages/nextjs`
  
### Notes
- Default network config targets Sei EVM via Alchemy; local dev is zero-config.
- This project scaffolding is based on 🏗 Scaffold-ETH 2. See their docs for patterns and helpers: [docs.scaffoldeth.io](https://docs.scaffoldeth.io).

### Quickstart
```bash
yarn install
# Tests on SEI fork (ALCHEMY_API_KEY required)
echo "ALCHEMY_API_KEY=your_alchemy_key" > packages/hardhat/.env
yarn test

# Optional: run frontend for demo
yarn start     # http://localhost:3000
```
Visit `http://localhost:3000/debug` to interact with contracts.

### Tests (packages/hardhat)
```bash
cd packages/hardhat
echo "ALCHEMY_API_KEY=your_alchemy_key" > .env
yarn test
```
- Runs on SEI mainnet fork (no localhost chain).
- Required: `ALCHEMY_API_KEY` in `packages/hardhat/.env` (or set `SEI_RPC_URL` instead).

### Deploy to SEI
```bash
# 1) Configure deployer key (stores encrypted key in packages/hardhat/.env)
yarn account:import   # or: yarn account:generate

# 2) Deploy (default network is 'sei')
yarn deploy
```

### Scripts you’ll use
- **yarn deploy**: deploy contracts to SEI (uses encrypted key)
- **yarn start**: run the frontend
- **yarn test**: run contract tests (workspace proxy to Hardhat)

