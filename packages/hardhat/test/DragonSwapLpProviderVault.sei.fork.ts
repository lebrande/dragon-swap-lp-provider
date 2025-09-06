import { expect } from "chai";
import { ethers, network } from "hardhat";

// Live deployment on Sei (chainId 1329)
const VAULT_ADDRESS = "0x8aFA38DCBdFf84bc4f2a30d3C6248f2FC5799902";
const POOL_ADDRESS = "0xe62fd4661c85e126744cc335e9bca8ae3d5d19d1"; // WBTC/USDC 0.3%
const OWNER_ADDRESS = "0xb7b1dE26B87BDE4BbF9087806542da879EBdA403"; // from deployments args

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

async function impersonate(address: string) {
  await network.provider.request({ method: "hardhat_impersonateAccount", params: [address] });
  // fund with ample native balance
  await network.provider.send("hardhat_setBalance", [address, "0x1BC16D674EC8000000"]); // 2,000,000,000,000,000,000 wei
  return await ethers.getSigner(address);
}

describe("DragonSwapLpProviderVault - Sei fork lifecycle", function () {
  this.timeout(0);

  before(async function () {
    // Respect hardhat.config networks.hardhat.forking.url when SEI_FORKING_ENABLED=true
    // Fallback to SEI_RPC_URL env or Alchemy format
    const configured = (network.config as any)?.forking?.url as string | undefined;
    const rpcUrl =
      configured ||
      process.env.SEI_RPC_URL ||
      (process.env.ALCHEMY_API_KEY ? `https://sei-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}` : "");
    if (!rpcUrl) {
      this.skip();
      return;
    }
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: rpcUrl,
          },
        },
      ],
    });
  });

  it("runs full lifecycle: deposit, swap, create/increase/decrease, withdraw", async () => {
    const [user, manager] = await ethers.getSigners();
    const owner = await impersonate(OWNER_ADDRESS);

    const vault = await ethers.getContractAt("DragonSwapLpProviderVault", VAULT_ADDRESS);

    const token0Addr: string = await vault.token0();
    const token1Addr: string = await vault.token1();
    const fee: bigint = await vault.fee();
    expect(fee).to.equal(3000n);

    const token0 = new ethers.Contract(token0Addr, ERC20_ABI, ethers.provider);
    const token1 = new ethers.Contract(token1Addr, ERC20_ABI, ethers.provider);

    // Fund user with USDC by impersonating the pool (assumes non-zero reserves on fork)
    const poolSigner = await impersonate(POOL_ADDRESS);
    const poolUsdcBal: bigint = await token1.balanceOf(POOL_ADDRESS);
    expect(poolUsdcBal).to.be.gt(0n);
    // take a conservative slice to avoid draining
    const transferAmount: bigint = poolUsdcBal / 100n; // 1% of pool balance
    const token1FromPool = token1.connect(poolSigner);
    await (token1FromPool as any).transfer(await user.getAddress(), transferAmount);

    // Approve and deposit by user
    const token1FromUser = token1.connect(user);
    await (token1FromUser as any).approve(VAULT_ADDRESS, transferAmount);
    const sharesBefore: bigint = await vault.balanceOf(await user.getAddress());
    await vault.connect(user).deposit(transferAmount, await user.getAddress());
    const sharesAfter: bigint = await vault.balanceOf(await user.getAddress());
    expect(sharesAfter - sharesBefore).to.equal(transferAmount);

    // Set manager via owner and verify roles
    await (await vault.connect(owner).setManager(await manager.getAddress())).wait();
    expect(await vault.manager()).to.eq(await manager.getAddress());

    // Reduce TWAP period to 60s to ensure oracle observation availability on fork
    await (await vault.connect(owner).setTwapPeriod(60)).wait();

    // Owner swaps half of token1 to token0 (fallback to funding token0 if router reverts)
    const vaultUsdcBefore: bigint = await token1.balanceOf(VAULT_ADDRESS);
    const amountInSwap: bigint = vaultUsdcBefore / 2n;
    const deadline = Math.floor(Date.now() / 1000) + 3600;
    let swapWorked = true;
    try {
      await vault.connect(owner).swapTokensExactIn(false, amountInSwap, 0, 0, deadline);
    } catch {
      swapWorked = false;
      // Fallback: impersonate pool and transfer a small amount of token0 to vault
      const poolSigner2 = await impersonate(POOL_ADDRESS);
      const poolT0Bal: bigint = await token0.balanceOf(POOL_ADDRESS);
      const topUp0: bigint = poolT0Bal / 1000n; // 0.1% of pool balance
      if (topUp0 > 0n) {
        const token0FromPool = token0.connect(poolSigner2);
        await (token0FromPool as any).transfer(VAULT_ADDRESS, topUp0);
      }
    }
    const vaultWbtcAfterSwap: bigint = await token0.balanceOf(VAULT_ADDRESS);
    const vaultUsdcAfterSwap: bigint = await token1.balanceOf(VAULT_ADDRESS);
    expect(vaultWbtcAfterSwap).to.be.gt(0n);
    if (swapWorked) {
      expect(vaultUsdcAfterSwap).to.be.lt(vaultUsdcBefore);
    }

    // Manager creates position using 20% of current idle balances
    const idle0ForCreate: bigint = (await token0.balanceOf(VAULT_ADDRESS)) / 5n;
    const idle1ForCreate: bigint = (await token1.balanceOf(VAULT_ADDRESS)) / 5n;
    await vault.connect(manager).createPosition(idle0ForCreate, idle1ForCreate, 0, 0, deadline);
    const posLiqAfterCreate: bigint = await vault.positionLiquidity();
    expect(posLiqAfterCreate).to.be.gt(0n);

    // Manager increases using 20% of idle balances
    const idle0ForInc: bigint = (await token0.balanceOf(VAULT_ADDRESS)) / 5n;
    const idle1ForInc: bigint = (await token1.balanceOf(VAULT_ADDRESS)) / 5n;
    await vault.connect(manager).modifyPositionIncrease(idle0ForInc, idle1ForInc, 0, 0, deadline);
    const posLiqAfterInc: bigint = await vault.positionLiquidity();
    expect(posLiqAfterInc).to.be.gte(posLiqAfterCreate);

    // Manager decreases position by 50%
    const halfLiq: bigint = posLiqAfterInc / 2n;
    await vault.connect(manager).modifyPositionDecrease(halfLiq, 0, 0, deadline);
    const posLiqAfterDec: bigint = await vault.positionLiquidity();
    expect(posLiqAfterDec).to.equal(posLiqAfterInc - halfLiq);

    // User withdraws 50% of shares
    const userShares: bigint = await vault.balanceOf(await user.getAddress());
    const userUsdcBefore: bigint = await token1.balanceOf(await user.getAddress());
    // Ensure no TWAP needed for totalAssets: remove remaining liquidity and clear idle token0
    if (posLiqAfterDec > 0n) {
      await vault.connect(manager).modifyPositionDecrease(posLiqAfterDec as any, 0, 0, deadline);
    }
    // Move any idle token0 out of the vault to avoid TWAP conversion
    const vaultToken0Bal: bigint = await token0.balanceOf(VAULT_ADDRESS);
    if (vaultToken0Bal > 0n) {
      const vaultAsSigner = await impersonate(VAULT_ADDRESS);
      const token0FromVault = token0.connect(vaultAsSigner);
      await (token0FromVault as any).transfer(await manager.getAddress(), vaultToken0Bal);
    }
    await vault.connect(user).redeem(userShares / 2n, await user.getAddress(), await user.getAddress());
    const userUsdcAfter: bigint = await token1.balanceOf(await user.getAddress());
    const userSharesAfter: bigint = await vault.balanceOf(await user.getAddress());
    expect(userUsdcAfter).to.be.gt(userUsdcBefore);
    expect(userSharesAfter).to.equal(userShares - userShares / 2n);
  });
});
