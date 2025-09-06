import { expect } from "chai";
import { ethers, network } from "hardhat";

// Fixed fork block (same as vault lifecycle test)
const FORK_BLOCK_NUMBER = 166614570;

// DragonSwap addresses (from deployment script)
const SWAP_ROUTER_ADDRESS = "0x11DA6463D6Cb5a03411Dbf5ab6f6bc3997Ac7428"; // SwapRouter02
const WBTC_ADDRESS = "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"; // token0
const USDC_ADDRESS = "0xe15fC38F6D8c56aF07bbCBe3BAf5708A2Bf42392"; // token1
const POOL_FEE = 3000; // 0.3%

// Known USDC rich account on Sei mainnet fork used in other tests
const USDC_WHALE_ADDRESS = "0x11235534a66A33c366b84933D5202c841539D1C9";

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

// Minimal ABI for DragonSwap V2 SwapRouter exactInputSingle
const SWAP_ROUTER_ABI = [
  {
    inputs: [
      {
        components: [
          { internalType: "address", name: "tokenIn", type: "address" },
          { internalType: "address", name: "tokenOut", type: "address" },
          { internalType: "uint24", name: "fee", type: "uint24" },
          { internalType: "address", name: "recipient", type: "address" },
          { internalType: "uint256", name: "amountIn", type: "uint256" },
          { internalType: "uint256", name: "amountOutMinimum", type: "uint256" },
          { internalType: "uint160", name: "sqrtPriceLimitX96", type: "uint160" },
        ],
        internalType: "struct IV2SwapRouter.ExactInputSingleParams",
        name: "params",
        type: "tuple",
      },
    ],
    name: "exactInputSingle",
    outputs: [{ internalType: "uint256", name: "amountOut", type: "uint256" }],
    stateMutability: "payable",
    type: "function",
  },
];

async function impersonate(address: string) {
  await network.provider.request({ method: "hardhat_impersonateAccount", params: [address] });
  // Fund with ample native balance
  await network.provider.send("hardhat_setBalance", [address, "0x1BC16D674EC8000000"]); // 2e18 wei
  return await ethers.getSigner(address);
}

describe("DragonSwap Router - Sei fork exactInputSingle USDC->WBTC", function () {
  this.timeout(0);

  before(async function () {
    // Respect hardhat.config networks.hardhat.forking.url when SEI_FORKING_ENABLED=true
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

  it("swaps 10 USDC for WBTC via exactInputSingle", async () => {
    const [user] = await ethers.getSigners();

    const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, ethers.provider);
    const wbtc = new ethers.Contract(WBTC_ADDRESS, ERC20_ABI, ethers.provider);
    const router = new ethers.Contract(SWAP_ROUTER_ADDRESS, SWAP_ROUTER_ABI, ethers.provider);

    // Fund user with 10 USDC from whale
    const whaleSigner = await impersonate(USDC_WHALE_ADDRESS);
    const whaleUsdcBal: bigint = await usdc.balanceOf(USDC_WHALE_ADDRESS);
    expect(whaleUsdcBal).to.equal(429208_883592n);
    const amountIn: bigint = 10_000000n; // 10 USDC (6 decimals)
    await (usdc.connect(whaleSigner) as any).transfer(await user.getAddress(), amountIn);

    // Approve router to spend user's USDC
    const userUsdcBefore: bigint = await usdc.balanceOf(await user.getAddress());
    expect(userUsdcBefore).to.equal(amountIn);
    await (usdc.connect(user) as any).approve(SWAP_ROUTER_ADDRESS, amountIn);

    // Record WBTC before
    const userWbtcBefore: bigint = await wbtc.balanceOf(await user.getAddress());
    expect(userWbtcBefore).to.equal(0n);

    // Execute exactInputSingle: USDC -> WBTC
    const routerFromUser = router.connect(user);
    const tx = await (routerFromUser as any).exactInputSingle({
      tokenIn: USDC_ADDRESS,
      tokenOut: WBTC_ADDRESS,
      fee: POOL_FEE,
      recipient: await user.getAddress(),
      amountIn: amountIn,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    });
    await tx.wait();

    // Validate balances
    const userUsdcAfter: bigint = await usdc.balanceOf(await user.getAddress());
    const userWbtcAfter: bigint = await wbtc.balanceOf(await user.getAddress());

    expect(userUsdcAfter).to.equal(0n);
    expect(userWbtcAfter).to.equal(9015n);
  });
});
