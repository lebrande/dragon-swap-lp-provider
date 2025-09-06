For DragonSwapLpProviderVault write test for sequence of actions:
Run tests against sei fork on already deployed vault smart contract.

There is an user and vault manager. That are two separate addresses.

- user approves USDC to be spent by the vault and deposits USDC to the vault
- vault manager swaps half of assets to the token0
- vault manager creates a position in the Dragon Swap pool using 20% of assets
- vault manager increase the position using 20% of idle assets
- vault manager decrease the position by 50%
- user withdraw 50% of their shares