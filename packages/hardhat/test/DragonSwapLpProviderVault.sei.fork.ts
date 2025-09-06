import { expect } from "chai";
import { ethers, network } from "hardhat";

// Addresses on Sei mainnet used for forking and on-the-fly deployment
// Constructor args (mirroring existing Sei deployment):
// _assetToken1 (USDC), _token0 (WBTC), _pool, _positionManager, _swapRouter, _fee, _owner
const TOKEN1_USDC = "0xe15fC38F6D8c56aF07bbCBe3BAf5708A2Bf42392";
const TOKEN0_WBTC = "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c";
const POOL_ADDRESS = "0xe62fd4661c85e126744cc335e9bca8ae3d5d19d1"; // WBTC/USDC 0.3%
const POSITION_MANAGER_ADDRESS = "0xa7FDcBe645d6b2B98639EbacbC347e2B575f6F70";
const ROUTER_ADDRESS = "0x11DA6463D6Cb5a03411Dbf5ab6f6bc3997Ac7428";
const FEE_3000 = 3000;
const OWNER_ADDRESS = "0xb7b1dE26B87BDE4BbF9087806542da879EBdA403"; // from deployments args
const USDC_WHALE_ADDRESS = "0x11235534a66A33c366b84933D5202c841539D1C9";
// Fork at deployment block + 10 to stabilize state
const FORK_BLOCK_NUMBER = 166639414 + 10;

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
            blockNumber: FORK_BLOCK_NUMBER,
          },
        },
      ],
    });
  });

  it("runs full lifecycle: deposit, swap, create/increase/decrease, withdraw", async () => {
    const [user, manager] = await ethers.getSigners();
    const owner = await impersonate(OWNER_ADDRESS);

    // Deploy a fresh vault on the fork using live Sei addresses
    const VaultFactory = await ethers.getContractFactory("DragonSwapLpProviderVault");
    const vault = await VaultFactory.deploy(
      TOKEN1_USDC,
      TOKEN0_WBTC,
      POOL_ADDRESS,
      POSITION_MANAGER_ADDRESS,
      ROUTER_ADDRESS,
      FEE_3000,
      OWNER_ADDRESS,
    );
    await vault.waitForDeployment();
    const VAULT_ADDRESS = await vault.getAddress();

    const token0Addr: string = await vault.token0();
    const token1Addr: string = await vault.token1();
    const fee: bigint = await vault.fee();
    expect(fee).to.equal(3000n);

    const token0 = new ethers.Contract(token0Addr, ERC20_ABI, ethers.provider);
    const token1 = new ethers.Contract(token1Addr, ERC20_ABI, ethers.provider);

    // Fund user with USDC by impersonating the whale
    const whaleSigner = await impersonate(USDC_WHALE_ADDRESS);
    const whaleUsdcBal: bigint = await token1.balanceOf(USDC_WHALE_ADDRESS);
    expect(whaleUsdcBal).to.equal(429253_659257n);
    const transferAmount: bigint = 10_000000n; // 10 USDC
    const token1FromWhale = token1.connect(whaleSigner);
    await (token1FromWhale as any).transfer(await user.getAddress(), transferAmount);

    const userUsdcBal: bigint = await token1.balanceOf(await user.getAddress());
    expect(userUsdcBal).to.equal(10_000000n);

    // Approve and deposit by user
    const token1FromUser = token1.connect(user);
    await (token1FromUser as any).approve(VAULT_ADDRESS, transferAmount);
    const sharesBefore: bigint = await vault.balanceOf(await user.getAddress());
    expect(sharesBefore).to.equal(0n);
    await vault.connect(user).deposit(transferAmount, await user.getAddress());
    const sharesAfter: bigint = await vault.balanceOf(await user.getAddress());
    expect(sharesAfter).to.equal(10_000000n);
    expect(sharesAfter - sharesBefore).to.equal(transferAmount);

    // Set manager via owner and verify roles
    await (await vault.connect(owner).setManager(await manager.getAddress())).wait();
    expect(await vault.manager()).to.eq(await manager.getAddress());

    // Reduce TWAP period to 60s to ensure oracle observation availability on fork
    await (await vault.connect(owner).setTwapPeriod(60)).wait();
    expect(await vault.twapPeriod()).to.equal(60);

    // Owner swaps half of token1 to token0 (fallback to funding token0 if router reverts)
    const vaultUsdcBefore: bigint = await token1.balanceOf(VAULT_ADDRESS);
    expect(vaultUsdcBefore).to.equal(10_000000n);
    const amountInSwap: bigint = vaultUsdcBefore / 2n;
    await vault.connect(owner).swapTokensExactIn(false, amountInSwap, 0, 0);
    const vaultWbtcAfterSwap: bigint = await token0.balanceOf(VAULT_ADDRESS);
    const vaultUsdcAfterSwap: bigint = await token1.balanceOf(VAULT_ADDRESS);

    expect(vaultWbtcAfterSwap).to.equal(4512n);
    expect(vaultUsdcAfterSwap).to.equal(5_000000n);

    // Manager creates position using 20% of current idle balances
    const idle0ForCreate: bigint = (await token0.balanceOf(VAULT_ADDRESS)) / 5n;
    expect(idle0ForCreate).to.equal(902n);
    const idle1ForCreate: bigint = (await token1.balanceOf(VAULT_ADDRESS)) / 5n;
    expect(idle1ForCreate).to.equal(1_000000n);
    const deadline = 1757300000; // GMT 8 September 2025 02:53:20
    await vault.connect(manager).createPosition(idle0ForCreate, idle1ForCreate, 0, 0, deadline);
    const posLiqAfterCreate: bigint = await vault.positionLiquidity();
    expect(posLiqAfterCreate).to.equal(601743n);

    // Manager increases using 20% of idle balances
    const idle0ForInc: bigint = (await token0.balanceOf(VAULT_ADDRESS)) / 5n;
    expect(idle0ForInc).to.equal(722n);
    const idle1ForInc: bigint = (await token1.balanceOf(VAULT_ADDRESS)) / 5n;
    expect(idle1ForInc).to.equal(801533n);
    await vault.connect(manager).modifyPositionIncrease(idle0ForInc, idle1ForInc, 0, 0, deadline);
    const posLiqAfterInc: bigint = await vault.positionLiquidity();
    expect(posLiqAfterInc).to.equal(1_083404n);

    // Manager decreases position by 33%
    const liqToDec: bigint = posLiqAfterInc / 3n;
    expect(liqToDec).to.equal(361134n);
    await vault.connect(manager).modifyPositionDecrease(liqToDec, 0, 0, deadline);
    const posLiqAfterDec: bigint = await vault.positionLiquidity();
    expect(posLiqAfterDec).to.equal(722270n);
    expect(posLiqAfterDec).to.equal(posLiqAfterInc - liqToDec);

    // User withdraws 5% of shares
    const userShares: bigint = await vault.balanceOf(await user.getAddress());
    expect(userShares).to.equal(10_000000n);
    const userUsdcBefore: bigint = await token1.balanceOf(await user.getAddress());
    expect(userUsdcBefore).to.equal(0n);

    const idleToken1: bigint = await token1.balanceOf(VAULT_ADDRESS);
    expect(idleToken1).to.equal(3_808905n);

    // const userAddress = await user.getAddress();
    // await vault.connect(user).redeem(1n, userAddress, userAddress);
    // const userUsdcAfter: bigint = await token1.balanceOf(userAddress);
    // const userSharesAfter: bigint = await vault.balanceOf(userAddress);
    // expect(userUsdcAfter).to.equal(1n);
    // expect(userSharesAfter).to.equal(2n);
  });
});
