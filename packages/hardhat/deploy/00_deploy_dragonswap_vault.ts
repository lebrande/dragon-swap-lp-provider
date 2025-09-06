import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

// SEI mainnet chainId 1329 DragonSwap V3-compatible addresses (from docs)
// https://docs.dragonswap.app/dragonswap/faq/contract-addresses/dragonswapv2
const DRAGON_ADDRESSES = {
  NonfungiblePositionManager: "0xa7FDcBe645d6b2B98639EbacbC347e2B575f6F70",
  SwapRouter02: "0x11DA6463D6Cb5a03411Dbf5ab6f6bc3997Ac7428",
  QuoterV2: "0x38F759cf0Af1D0dcAEd723a3967A3B658738eDe9",
  Factory: "0x179D9a5592Bc77050796F7be28058c51cA575df4",
};

const POOL = {
  address: "0xe62fd4661c85e126744cc335e9bca8ae3d5d19d1",
  token0: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", // WBTC
  token1: "0xe15fC38F6D8c56aF07bbCBe3BAf5708A2Bf42392", // USDC
  fee: 3000, // 0.3%
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  log(`Deploying DragonSwapLpProviderVault to network ${network.name} (chainId=${network.config.chainId})`);

  const manager = process.env.VAULT_MANAGER ?? deployer;
  const owner = process.env.VAULT_OWNER ?? deployer;

  const deployment = await deploy("DragonSwapLpProviderVault", {
    from: deployer,
    args: [
      POOL.token1, // that's also underlying asset of the vault
      POOL.token0,
      POOL.address,
      DRAGON_ADDRESSES.NonfungiblePositionManager,
      DRAGON_ADDRESSES.SwapRouter02,
      POOL.fee,
      owner,
    ],
    log: true,
    autoMine: true,
  });

  const vault = await ethers.getContractAt("DragonSwapLpProviderVault", deployment.address);
  const tx = await vault.setManager(manager);
  await tx.wait();
  log(`Vault deployed at ${deployment.address}, manager set to ${manager}`);
};

export default func;
func.tags = ["DragonVault"];

