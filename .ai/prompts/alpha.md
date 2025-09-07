You are an expert of Uniswap and Vaults

Steps for automate process of changing ranges for Uniswap V3
Script should be created by on hardhat tests from `test-resource`
Read Dragon Swap documentation in `dragon-swap-docs`:
Script will be using setInterval like 10 seconds.

Vault automate providing liquidity to the Dragon Swap pools (concentrated liquidity). The vault is a single liquidity provider which represents all the vault depositors and perform on behalf of depositors. Vault manager is an entity that triggers transactions to modify LP position to keep vault profiting by keeping the position always in the range.

- create script in folder `automation`
- Scipt will be in Typescript using `ethers` library check `https://docs.ethers.org/v6/`
- Liqudidty provider is our Vault that is in `packages\hardhat\contracts\DragonSwapLpProviderVault.sol`
- Dragon Swap is a fork of Uniswap V3 (concentrated liquidity)
  <test-resource>
  packages\hardhat\test\DragonSwapLpProviderVault.sei.fork.ts
  packages\hardhat\test\DragonSwapLpProviderVault.ts
  </test-resource>

Read Dragon Swap documentation in `dragon-swap-docs`:
<dragon-swap-docs>
https://docs.dragonswap.app/dragonswap/guides/liqudity-providers/v2-concentrated-liquidity-pools
https://docs.dragonswap.app/dragonswap/faq/contract-addresses/dragonswapv2
https://docs.dragonswap.app/dragonswap/resources/developer-resources/smart-contracts/dragonswapv2
</dragon-swap-docs>

Vault Address `0x8aFA38DCBdFf84bc4f2a30d3C6248f2FC5799902`
chain is SEI, chainId=1329
