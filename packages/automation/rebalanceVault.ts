import "dotenv/config";
import {
  Contract,
  JsonRpcProvider,
  Wallet,
  formatUnits,
  getAddress,
} from "ethers";

const DEFAULT_INTERVAL_MS = 10_000;

// Minimal ABIs extracted from the contract and tests
const VAULT_ABI = [
  "function pool() view returns (address)",
  "function token0() view returns (address)",
  "function token1() view returns (address)",
  "function fee() view returns (uint24)",
  "function manager() view returns (address)",
  "function owner() view returns (address)",
  "function positionTokenId() view returns (uint256)",
  "function positionLiquidity() view returns (uint128)",
  "function positionTickLower() view returns (int24)",
  "function positionTickUpper() view returns (int24)",
  "function setManager(address _manager)",
  "function createPosition(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline) returns (uint256 tokenId, uint128 liquidity)",
  "function modifyPositionIncrease(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline) returns (uint128 liquidity, uint256 used0, uint256 used1)",
  "function modifyPositionDecrease(uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline) returns (uint256 amount0, uint256 amount1)",
  "function collectRewards() returns (uint256 amount0, uint256 amount1)",
  "function swapTokensExactIn(bool zeroForOne, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96) returns (uint256 amountOut)",
];

const POOL_ABI = [
  "function slot0() view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)",
  "function tickSpacing() view returns (int24)",
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

type Signers = {
  manager?: Wallet;
  owner?: Wallet;
};

function requireEnv(name: string): string {
  const val = process.env[name];
  if (!val || val.trim() === "") throw new Error(`Missing env ${name}`);
  return val.trim();
}

async function ensureRoles(vault: Contract, signers: Signers) {
  const onchainManager: string = await vault.manager();
  const onchainOwner: string = await vault.owner();
  if (!signers.manager && !signers.owner) {
    throw new Error(
      "At least MANAGER_PRIVATE_KEY or OWNER_PRIVATE_KEY must be provided"
    );
  }
  if (
    signers.manager &&
    getAddress(onchainManager) !== getAddress(signers.manager.address)
  ) {
    console.warn(
      `Manager mismatch: on-chain ${onchainManager} vs provided ${signers.manager.address}`
    );
  }
  if (
    signers.owner &&
    getAddress(onchainOwner) !== getAddress(signers.owner.address)
  ) {
    console.warn(
      `Owner mismatch: on-chain ${onchainOwner} vs provided ${signers.owner.address}`
    );
  }
}

async function main() {
  const VAULT_ADDRESS = (
    process.env.VAULT_ADDRESS || "0x8aFA38DCBdFf84bc4f2a30d3C6248f2FC5799902"
  ).trim();
  const RPC_URL = requireEnv("SEI_RPC_URL");
  const INTERVAL_MS = Number(
    process.env.AUTOMATION_INTERVAL_MS || DEFAULT_INTERVAL_MS
  );

  const provider = new JsonRpcProvider(RPC_URL, { name: "sei", chainId: 1329 });

  const managerPk = process.env.MANAGER_PRIVATE_KEY?.trim();
  const ownerPk = process.env.OWNER_PRIVATE_KEY?.trim();
  const signers: Signers = {};
  if (managerPk) signers.manager = new Wallet(managerPk, provider);
  if (ownerPk) signers.owner = new Wallet(ownerPk, provider);

  // Use provider-backed contract for reads; connect signer only for writes
  const vaultRead = new Contract(VAULT_ADDRESS, VAULT_ABI, provider);

  const envPool = process.env.POOL_ADDRESS?.trim();
  const poolAddr: string =
    envPool && envPool !== "" ? envPool : await vaultRead.pool();
  const token0Addr: string = await vaultRead.token0();
  const token1Addr: string = await vaultRead.token1();
  const feeBps: bigint = await vaultRead.fee();
  const [onchainManager, onchainOwner, posIdAtStart] = await Promise.all([
    vaultRead.manager(),
    vaultRead.owner(),
    vaultRead.positionTokenId(),
  ]);

  const pool = new Contract(poolAddr, POOL_ABI, provider);
  const token0 = new Contract(token0Addr, ERC20_ABI, provider);
  const token1 = new Contract(token1Addr, ERC20_ABI, provider);

  const [dec0Raw, dec1Raw, sym0, sym1] = await Promise.all([
    token0.decimals(),
    token1.decimals(),
    token0.symbol(),
    token1.symbol(),
  ]);
  const dec0 = Number(dec0Raw);
  const dec1 = Number(dec1Raw);

  console.log("Automation started");
  console.log(`- Network: SEI (chainId 1329)`);
  console.log(`- Vault: ${VAULT_ADDRESS}`);
  console.log(`- Pool:  ${poolAddr}`);
  console.log(`- Pair:  ${sym0}/${sym1} fee ${Number(feeBps) / 10_000}%`);
  console.log(
    `- Owner: ${onchainOwner}${
      signers.owner ? ` (provided ${signers.owner.address})` : ""
    }`
  );
  console.log(
    `- Manager: ${onchainManager}${
      signers.manager ? ` (provided ${signers.manager.address})` : ""
    }`
  );
  console.log(`- Position tokenId: ${posIdAtStart.toString()}`);
  console.log(`- Interval: ${INTERVAL_MS} ms`);

  // Optionally set manager via owner if AUTO_SET_MANAGER=true
  if (signers.owner && process.env.AUTO_SET_MANAGER === "true") {
    const desiredManager =
      process.env.MANAGER_ADDRESS?.trim() ||
      signers.manager?.address ||
      signers.owner.address;
    try {
      if (getAddress(onchainManager) !== getAddress(desiredManager)) {
        const tx = await vaultRead
          .connect(signers.owner)
          .setManager(desiredManager);
        await tx.wait();
        console.log(`  ✓ Manager updated to ${desiredManager}`);
      }
    } catch (e) {
      console.warn("  ! setManager failed:", (e as any)?.message || e);
    }
  }

  let running = false;

  const step = async () => {
    if (running) return; // prevent overlapping
    running = true;
    const now = Math.floor(Date.now() / 1000);
    try {
      const [posId, posLiq, tickL, tickU] = await Promise.all([
        vaultRead.positionTokenId(),
        vaultRead.positionLiquidity(),
        vaultRead.positionTickLower(),
        vaultRead.positionTickUpper(),
      ]);

      const slot0 = await pool.slot0();
      const sqrtPriceX96: bigint = slot0[0];
      const currentTickBi: bigint = slot0[1];
      const spacingBi: bigint = await pool.tickSpacing();
      const currentTick = Number(currentTickBi);
      const spacing = Number(spacingBi);

      const gridLower = Math.floor(currentTick / spacing) * spacing;
      const gridUpper = Math.ceil(currentTick / spacing) * spacing;

      const inRange =
        currentTick > Number(tickL) && currentTick < Number(tickU);

      const [bal0Raw, bal1Raw] = await Promise.all([
        token0.balanceOf(VAULT_ADDRESS),
        token1.balanceOf(VAULT_ADDRESS),
      ]);

      const bal0 = BigInt(bal0Raw);
      const bal1 = BigInt(bal1Raw);
      const liq = BigInt(posLiq);

      console.log(
        `[${new Date().toISOString()}] poolTick=${currentTick} poolGrid=[${gridLower}, ${gridUpper}] spacing=${spacing} sqrtP=${sqrtPriceX96.toString()}`
      );
      console.log(`  vaultRange=[${tickL}, ${tickU}] inRange=${inRange}`);
      console.log(
        `  idle: ${formatUnits(bal0, dec0)} ${sym0}, ${formatUnits(
          bal1,
          dec1
        )} ${sym1}; liq=${liq}`
      );

      // 1) Periodically collect rewards if any position exists
      if (posId !== 0n && signers.manager) {
        try {
          const tx = await vaultRead.connect(signers.manager).collectRewards();
          await tx.wait();
          console.log("  ✓ Rewards collected");
        } catch (e) {
          // ignore if no fees or revert
        }
      }

      // 2) If out-of-range and there is liquidity, unload to idle to avoid IL
      if (!inRange && liq > 0n && signers.manager) {
        try {
          const tx = await vaultRead
            .connect(signers.manager)
            .modifyPositionDecrease(liq, 0, 0, now + 600);
          await tx.wait();
          console.log("  ✓ Decreased all liquidity (out of range)");
        } catch (e) {
          console.warn(
            "  ! Decrease liquidity failed:",
            (e as any)?.message || e
          );
        }
      }

      // 3) If no position minted yet (tokenId==0), try to create a fresh one with a conservative slice of idle balances
      if (posId === 0n && signers.manager) {
        let use0 = bal0 / 5n; // 20%
        let use1 = bal1 / 5n; // 20%

        // If centered range and one side is zero, use owner to perform a small swap to seed the missing side
        if (
          (use0 === 0n || use1 === 0n) &&
          signers.owner &&
          (bal0 > 0n || bal1 > 0n)
        ) {
          try {
            const swapPortion = 10n; // 10%
            if (bal1 > 0n && bal0 === 0n) {
              const amountIn = bal1 / swapPortion;
              if (amountIn > 0n) {
                const txSwap = await vaultRead
                  .connect(signers.owner)
                  .swapTokensExactIn(false, amountIn, 0, 0); // token1 -> token0
                await txSwap.wait();
                console.log(
                  `  ✓ Swapped ${formatUnits(
                    amountIn,
                    dec1
                  )} ${sym1} -> ${sym0} to seed createPosition`
                );
              }
            } else if (bal0 > 0n && bal1 === 0n) {
              const amountIn = bal0 / swapPortion;
              if (amountIn > 0n) {
                const txSwap = await vaultRead
                  .connect(signers.owner)
                  .swapTokensExactIn(true, amountIn, 0, 0); // token0 -> token1
                await txSwap.wait();
                console.log(
                  `  ✓ Swapped ${formatUnits(
                    amountIn,
                    dec0
                  )} ${sym0} -> ${sym1} to seed createPosition`
                );
              }
            }
          } catch (e) {
            console.warn("  ! Seed swap failed:", (e as any)?.message || e);
          }
          // refresh idle balances after swap
          const [nb0, nb1] = await Promise.all([
            token0.balanceOf(VAULT_ADDRESS),
            token1.balanceOf(VAULT_ADDRESS),
          ]);
          use0 = BigInt(nb0) / 5n;
          use1 = BigInt(nb1) / 5n;
        }

        if (use0 > 0n && use1 > 0n) {
          try {
            const tx = await vaultRead
              .connect(signers.manager)
              .createPosition(use0, use1, 0, 0, now + 600);
            await tx.wait();
            console.log("  ✓ Created new position");
          } catch (e) {
            console.warn(
              "  ! Create position failed:",
              (e as any)?.message || e
            );
          }
        }
      }

      // 4) If in range and there is meaningful idle balance, add some liquidity
      if (inRange && signers.manager) {
        const threshold0 = 10n ** BigInt(Math.max(0, dec0 - 4)); // ~1e-4 units of token0
        const threshold1 = 10n ** BigInt(Math.max(0, dec1 - 2)); // ~1e-2 units of token1
        const add0 = bal0 / 10n; // 10%
        const add1 = bal1 / 10n; // 10%
        // Prefer adding when both sides available for centered range
        if (add0 > threshold0 && add1 > threshold1) {
          try {
            const tx = await vaultRead
              .connect(signers.manager)
              .modifyPositionIncrease(add0, add1, 0, 0, now + 600);
            await tx.wait();
            console.log("  ✓ Increased liquidity");
          } catch (e) {
            console.warn(
              "  ! Increase liquidity failed:",
              (e as any)?.message || e
            );
          }
        }
      }

      // 5) Clarify zero-liquidity state
      if (liq === 0n) {
        if (posId === 0n) {
          console.warn(
            "  ! No position minted (posId=0). Deposit assets and ensure MANAGER_PRIVATE_KEY has role to create."
          );
        } else if (!inRange) {
          console.warn(
            "  ! Position out of range and no liquidity. Waiting for funds or manual intervention."
          );
        }
      }
    } catch (err) {
      console.error("Step error:", (err as any)?.message || err);
    } finally {
      running = false;
    }
  };

  // kick-off and interval loop
  await step();
  setInterval(step, INTERVAL_MS);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
