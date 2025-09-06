import { expect } from "chai";
import { ethers, deployments } from "hardhat";

describe("DragonSwapLpProviderVault - ERC4626 core and access control", function () {
  const NAME = "DragonSwap USDC DEX LP";
  const SYMBOL = "DRGusdc";

  beforeEach(async () => {
    await deployments.fixture([]);
  });

  async function deployFixture() {
    const [deployer, manager, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const token0 = await MockERC20.deploy("Token0", "TK0", 18);
    const token1 = await MockERC20.deploy("Token1", "TK1", 6);
    await token0.waitForDeployment();
    await token1.waitForDeployment();

    // Minimal pool/manager/router mocks
    const poolMock = await (await ethers.getContractFactory("PoolMock"))
      .deploy();
    await poolMock.waitForDeployment();

    const positionManagerMock = await (await ethers.getContractFactory("PositionManagerMock"))
      .deploy(token0.getAddress(), token1.getAddress());
    await positionManagerMock.waitForDeployment();

    const routerMock = await (await ethers.getContractFactory("RouterMock"))
      .deploy(token0.getAddress(), token1.getAddress());
    await routerMock.waitForDeployment();

    const Vault = await ethers.getContractFactory("DragonSwapLpProviderVault");
    const vault = await Vault.deploy(
      await token1.getAddress(),
      await token0.getAddress(),
      await poolMock.getAddress(),
      await positionManagerMock.getAddress(),
      await routerMock.getAddress(),
      3000,
      await deployer.getAddress()
    );
    await vault.waitForDeployment();
    await (await vault.setManager(await manager.getAddress())).wait();

    return { deployer, manager, user, token0, token1, vault, poolMock, positionManagerMock, routerMock };
  }

  it("initializes metadata", async () => {
    const { vault } = await deployFixture();
    expect(await vault.name()).to.eq(NAME);
    expect(await vault.symbol()).to.eq(SYMBOL);
    expect(await vault.asset()).to.properAddress;
  });

  it("deposits and mints shares 1:1 when empty", async () => {
    const { user, token1, vault } = await deployFixture();
    await token1.mint(await user.getAddress(), 1_000_000n);
    await token1.connect(user).approve(await vault.getAddress(), 1_000_000n);
    // const shares = await vault.connect(user).deposit(500_000n, await user.getAddress());
    expect(await vault.balanceOf(await user.getAddress())).to.eq(500_000n);
    expect(await vault.totalAssets()).to.eq(500_000n);
  });

  it("withdraw respects access and returns asset", async () => {
    const { user, token1, vault } = await deployFixture();
    await token1.mint(await user.getAddress(), 1_000_000n);
    await token1.connect(user).approve(await vault.getAddress(), 1_000_000n);
    await vault.connect(user).deposit(700_000n, await user.getAddress());
    await expect(vault.connect(user).withdraw(200_000n, await user.getAddress(), await user.getAddress()))
      .to.emit(vault, "Withdraw");
    expect(await token1.balanceOf(await user.getAddress())).to.eq(500_000n);
  });

  it("only manager can create/modify/collect, only owner can swap", async () => {
    const { manager, user, vault } = await deployFixture();
    await expect(vault.connect(user).createPosition(0, 0, 0, 0, 0)).to.be.revertedWith("MANAGER");
    // Manager can call createPosition when no position exists
    // Since our mock manager requires liquidity inputs to mint, we expect it to revert with EXISTS only if already created.
    await expect(vault.connect(manager).createPosition(0, 0, 0, 0, 0)).to.not.be.reverted;
    await expect(vault.connect(user).modifyPositionIncrease(0, 0, 0, 0, 0)).to.be.revertedWith("MANAGER");
    await expect(vault.connect(user).modifyPositionDecrease(0, 0, 0, 0)).to.be.revertedWith("MANAGER");
    await expect(vault.connect(user).collectRewards()).to.be.revertedWith("MANAGER");
    await expect(vault.connect(user).swapTokensExactIn(true, 0, 0, 0)).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
  });
});


