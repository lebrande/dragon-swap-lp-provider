# How `automation/rebalanceVault.ts` works

- Starts a monitoring loop for `DragonSwapLpProviderVault` on SEI (chainId 1329).
- Every `AUTOMATION_INTERVAL_MS` it reads: `slot0` (tick, sqrtPrice), position range, token balances, `totalSupply`, `totalAssets`, and an approximate `pricePerShare` (skipping potential TWAP "OLD" revert).
- Optionally updates the manager when `AUTO_SET_MANAGER=true` (requires owner role).
- Collects fees (`collectRewards`) if a position exists and a manager key is provided.
- When the position is out of range: removes all liquidity back to idle funds.
- When there is no position: uses ~20% of idle funds to `createPosition`; if one asset is missing, the owner performs a small swap to seed it.
- When the position is in range and there are idle funds: adds liquidity (~10% of both assets above thresholds).
- Can watch addresses from `WATCH_ADDRESSES` (logs shares and approximate assets).
- Sends transactions only if proper keys are provided: `MANAGER_PRIVATE_KEY`/`OWNER_PRIVATE_KEY`; otherwise runs read-only.

Required environment variables:

- `SEI_RPC_URL`
- `VAULT_ADDRESS`
- `POOL_ADDRESS`
- `MANAGER_PRIVATE_KEY`
- `OWNER_PRIVATE_KEY`
- `MANAGER_ADDRESS`

  Optional environment variables:

- `AUTO_SET_MANAGER`
- `AUTOMATION_INTERVAL_MS` (default 1000 ms)
- `WATCH_ADDRESSES` (comma-separated list)

Run:

`npx tsx .\automation\rebalanceVault.ts`
