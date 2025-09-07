// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDragonV3Pool} from "./interfaces/IDragonV3Pool.sol";
import {IDragonNonfungiblePositionManager} from "./interfaces/IDragonNonfungiblePositionManager.sol";
import {IDragonSwapRouter} from "./interfaces/IDragonSwapRouter.sol";
import {TickMathLib} from "./libraries/TickMathLib.sol";
import {LiquidityAmountsLib} from "./libraries/LiquidityAmountsLib.sol";

/**
 * @title DragonSwap LP Provider Vault
 * @notice ERC-4626 compliant vault that deploys deposited `token1` capital as concentrated liquidity
 *         into a DragonSwap v3-like pool (`token0`/`token1`). The vault manages one position defined
 *         by a lower and upper tick and can rebalance liquidity, collect fees, and perform owner-only
 *         swaps to source withdrawal liquidity.
 *
 * @dev Concept overview for auditors:
 * - Share accounting: Standard ERC-4626. Deposits are in `asset` (token1). `totalAssets()` values all
 *   holdings in `token1` terms using the current spot price from the pool. This is a simplification
 *   (not a time-weighted price) and is acceptable for an internal NAV approximation.
 * - Liquidity position: The vault manages at most one LP NFT position (tracked by `positionTokenId`).
 *   Liquidity can be increased/decreased by the `manager`. Collected fees remain in the vault and are
 *   reflected in `totalAssets()`.
 * - Withdrawals: Prior to ERC-4626 `withdraw`/`redeem`, the vault attempts to free up `token1` by
 *   (1) using idle `token1`, (2) redeeming a proportional part of liquidity, and (3) swapping any idle
 *   `token0` to `token1` as a last resort. Reentrancy is guarded.
 * - Roles: `owner` can set `manager`, adjust TWAP period, and execute swaps. The `manager` can create
 *   the LP position, increase/decrease liquidity, and collect rewards.
 */
contract DragonSwapLpProviderVault is ERC4626, Ownable, ReentrancyGuard {
    using TickMathLib for int24;

    // Immutable config
    /// @notice Address of token0 in the underlying pool.
    address public immutable token0;
    /// @notice Address of token1 in the underlying pool and the ERC-4626 asset.
    address public immutable token1;
    /// @notice Underlying DragonSwap v3-like pool used for pricing and ticks.
    IDragonV3Pool public immutable pool;
    /// @notice Position manager that mints/burns v3 positions and collects fees.
    IDragonNonfungiblePositionManager public immutable positionManager;
    /// @notice Router used by the vault to perform swaps when sourcing liquidity.
    IDragonSwapRouter public immutable swapRouter;
    /// @notice Pool fee tier in hundredths of a bip, e.g., 3000 = 0.3%.
    uint24 public immutable fee; // 3000 = 0.3%

    // Manager role
    /// @notice Address with permission to manage liquidity and collect rewards.
    address public manager;

    // Position state
    /// @notice Token ID of the managed LP position (0 if not created yet).
    uint256 public positionTokenId;
    /// @notice Current liquidity of the managed position.
    uint128 public positionLiquidity;
    /// @notice Lower tick of the managed position.
    int24 public positionTickLower;
    /// @notice Upper tick of the managed position.
    int24 public positionTickUpper;

    // Valuation config
    /// @notice TWAP window in seconds used by price helpers. Constrained by `setTwapPeriod`.
    uint32 public twapPeriod = 300; // seconds, as specified

    // Range width config (in basis points, around mid tick)
    /// @dev Default width is +/- 10% around the current tick when creating a new position.
    uint16 public constant DEFAULT_RANGE_BPS = 1000; // +/-10%

    /// @notice Emitted when the `manager` address is updated.
    event ManagerUpdated(address indexed manager);
    /// @notice Emitted when a new position is created.
    event PositionCreated(uint256 indexed tokenId, uint128 liquidity, int24 tickLower, int24 tickUpper);
    /// @notice Emitted when liquidity is added to the existing position.
    event PositionIncreased(uint256 indexed tokenId, uint128 liquidityAdded, uint256 amount0, uint256 amount1);
    /// @notice Emitted when liquidity is removed from the existing position.
    event PositionDecreased(uint256 indexed tokenId, uint128 liquidityRemoved, uint256 amount0, uint256 amount1);
    /// @notice Emitted when fees/rewards are collected from the position.
    event RewardsCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    /// @notice Emitted when the vault executes a swap to source or rebalance assets.
    event TokensSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    modifier onlyManager() {
        // Keep error string as "MANAGER" to avoid breaking external integrations/tests
        require(msg.sender == manager, "MANAGER");
        _;
    }

    /**
     * @param _assetToken1 The asset of the vault (token1), i.e., deposit/withdraw token.
     * @param _token0 The other pool token paired with token1.
     * @param _pool The DragonSwap V3 pool address for token0/token1.
     * @param _positionManager Nonfungible position manager contract address.
     * @param _swapRouter Router used for swaps to fulfill withdrawals.
     * @param _fee Pool fee tier (e.g. 3000 = 0.3%).
     * @param _owner Initial owner of the vault.
     */
    constructor(
        address _assetToken1,
        address _token0,
        address _pool,
        address _positionManager,
        address _swapRouter,
        uint24 _fee,
        address _owner
    ) ERC20("DragonSwap USDC DEX LP", "DRGusdc") ERC4626(IERC20(_assetToken1)) Ownable(_owner) {
        require(_assetToken1 != address(0) && _token0 != address(0), "token0 and token1 must be non-zero addresses");
        require(
            _pool != address(0) && _positionManager != address(0) && _swapRouter != address(0),
            "pool, position manager, and router must be non-zero addresses"
        );
        token0 = _token0;
        token1 = _assetToken1;
        pool = IDragonV3Pool(_pool);
        positionManager = IDragonNonfungiblePositionManager(_positionManager);
        swapRouter = IDragonSwapRouter(_swapRouter);
        fee = _fee;
    }

    // -----------------------
    // Manager / Owner controls
    // -----------------------
    /**
     * @notice Sets or updates the address with manager permissions.
     * @param _manager The new manager address (can be zero to disable).
     */
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerUpdated(_manager);
    }

    /**
     * @notice Updates the TWAP window used by price helpers.
     * @dev Constrained to [60, 86400] seconds to avoid extreme configuration.
     * @param _period The new period in seconds.
     */
    function setTwapPeriod(uint32 _period) external onlyOwner {
        require(_period >= 60 && _period <= 86400, "Invalid TWAP period: must be between 60 and 86400 seconds");
        twapPeriod = _period;
    }

    // -----------------------
    // ERC4626 overrides
    // -----------------------
    /**
     * @notice Returns the total assets denominated in `token1`.
     * @dev Values on-position balances using the current spot price from the pool (not TWAP).
     *      This function approximates NAV for ERC-4626 accounting and is not intended for precise
     *      price oracle usage. Beware of potential manipulation if called in the same block as a swap.
     */
    function totalAssets() public view override returns (uint256) {
        // idle balances
        uint256 idle1 = IERC20(token1).balanceOf(address(this));
        uint256 idle0 = IERC20(token0).balanceOf(address(this));

        // Position amounts (token0, token1) estimated from current sqrt price and ticks
        uint256 pos0;
        uint256 pos1;
        if (positionLiquidity > 0) {
            (uint160 sqrtPriceX96,, , , , , ) = pool.slot0();
            uint160 sqrtLower = TickMathLib.getSqrtRatioAtTick(positionTickLower);
            uint160 sqrtUpper = TickMathLib.getSqrtRatioAtTick(positionTickUpper);
            (pos0, pos1) = LiquidityAmountsLib.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtLower,
                sqrtUpper,
                positionLiquidity
            );
        }

        // Convert everything to token1 using spot price only if needed
        uint256 idle0In1;
        uint256 pos0In1;
        if (idle0 > 0 || pos0 > 0) {
            uint256 priceX96 = _twapToken0PerToken1X96(); // Q96 (USES SPOT PRICE!)
            idle0In1 = (idle0 * priceX96) >> 96;
            pos0In1 = (pos0 * priceX96) >> 96;
        }

        return idle1 + pos1 + idle0In1 + pos0In1;
    }

    // Ensure liquidity and token1 are available for withdrawals/redeems
    /**
     * @inheritdoc ERC4626
     * @dev Prepares `token1` liquidity by redeeming a proportional share of the LP position and/or
     *      swapping idle `token0` if necessary. Guarded by nonReentrant.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        uint256 sharesNeeded = previewWithdraw(assets);
        _prepareAssetsForWithdrawal(assets, sharesNeeded);
        shares = super.withdraw(assets, receiver, owner);
    }

    /**
     * @inheritdoc ERC4626
     * @dev Prepares `token1` liquidity by redeeming a proportional share of the LP position and/or
     *      swapping idle `token0` if necessary. Guarded by nonReentrant.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        uint256 assetsNeeded = previewRedeem(shares);
        _prepareAssetsForWithdrawal(assetsNeeded, shares);
        assets = super.redeem(shares, receiver, owner);
    }

    // -----------------------
    // Manager operations
    // -----------------------
    /**
     * @notice Creates a new LP position around the current tick using DEFAULT_RANGE_BPS.
     * @param amount0Desired Desired amount of token0 to deposit as liquidity.
     * @param amount1Desired Desired amount of token1 to deposit as liquidity.
     * @param amount0Min Minimum token0 to be spent (slippage guard).
     * @param amount1Min Minimum token1 to be spent (slippage guard).
     * @param deadline Transaction deadline.
     * @return tokenId The new position token ID.
     * @return liquidity The liquidity minted for the position.
     */
    function createPosition(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyManager
        nonReentrant
        returns (uint256 tokenId, uint128 liquidity)
    {
        require(positionTokenId == 0, "Position already exists");

        ( , int24 currentTick, , , , , ) = pool.slot0();
        int24 spacing = pool.tickSpacing();
        int24 delta = int24(uint24(DEFAULT_RANGE_BPS)); // approx mapping: 1 tick ≈ 1 bps (heuristic)
        int24 tickLower = _floorTick(currentTick - delta, spacing);
        int24 tickUpper = _ceilTick(currentTick + delta, spacing);

        _approveIfNeeded(token0, address(positionManager), amount0Desired);
        _approveIfNeeded(token1, address(positionManager), amount1Desired);

        IDragonNonfungiblePositionManager.MintParams memory m = IDragonNonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: deadline
        });
        (tokenId, liquidity, , ) = positionManager.mint(m);

        positionTokenId = tokenId;
        positionLiquidity = liquidity;
        positionTickLower = tickLower;
        positionTickUpper = tickUpper;
        emit PositionCreated(tokenId, liquidity, tickLower, tickUpper);
    }

    /**
     * @notice Increases liquidity on the existing position.
     * @param amount0Desired Desired token0 to add.
     * @param amount1Desired Desired token1 to add.
     * @param amount0Min Minimum token0 to add (slippage guard).
     * @param amount1Min Minimum token1 to add (slippage guard).
     * @param deadline Transaction deadline.
     * @return liquidity Liquidity added.
     * @return used0 Actual token0 used by the position manager.
     * @return used1 Actual token1 used by the position manager.
     */
    function modifyPositionIncrease(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyManager
        nonReentrant
        returns (uint128 liquidity, uint256 used0, uint256 used1)
    {
        require(positionTokenId != 0, "No active position");
        _approveIfNeeded(token0, address(positionManager), amount0Desired);
        _approveIfNeeded(token1, address(positionManager), amount1Desired);
        IDragonNonfungiblePositionManager.IncreaseLiquidityParams memory p = IDragonNonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: positionTokenId,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: deadline
        });
        (liquidity, used0, used1) = positionManager.increaseLiquidity(p);
        positionLiquidity += liquidity;
        emit PositionIncreased(positionTokenId, liquidity, used0, used1);
    }

    /**
     * @notice Decreases liquidity on the existing position and collects tokens + fees.
     * @param liquidity The liquidity to remove.
     * @param amount0Min Minimum token0 to receive (slippage guard).
     * @param amount1Min Minimum token1 to receive (slippage guard).
     * @param deadline Transaction deadline.
     * @return amount0 Token0 received.
     * @return amount1 Token1 received.
     */
    function modifyPositionDecrease(uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyManager
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(positionTokenId != 0, "No active position");
        IDragonNonfungiblePositionManager.DecreaseLiquidityParams memory p = IDragonNonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: positionTokenId,
            liquidity: liquidity,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: deadline
        });
        (amount0, amount1) = positionManager.decreaseLiquidity(p);
        IDragonNonfungiblePositionManager.CollectParams memory c = IDragonNonfungiblePositionManager.CollectParams({
            tokenId: positionTokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        positionManager.collect(c);
        positionLiquidity -= liquidity;
        emit PositionDecreased(positionTokenId, liquidity, amount0, amount1);
    }

    /**
     * @notice Collects all fees/rewards accrued to the current position.
     * @return amount0 Token0 fees collected.
     * @return amount1 Token1 fees collected.
     */
    function collectRewards() external onlyManager nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(positionTokenId != 0, "No active position");
        IDragonNonfungiblePositionManager.CollectParams memory p = IDragonNonfungiblePositionManager.CollectParams({
            tokenId: positionTokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (amount0, amount1) = positionManager.collect(p);
        emit RewardsCollected(positionTokenId, amount0, amount1);
    }

    // -----------------------
    // Owner operations: swaps
    // -----------------------
    /**
     * @notice Executes an exact-in swap to convert between token0 and token1.
     * @dev Owner-only. Used to source `token1` for withdrawals or to rebalance idle assets.
     * @param zeroForOne If true, swap token0->token1; otherwise token1->token0.
     * @param amountIn Input amount for the swap.
     * @param amountOutMinimum Minimum amount out (slippage guard).
     * @param sqrtPriceLimitX96 Price limit for the swap.
     * @return amountOut The amount of tokens received from the swap.
     */
    function swapTokensExactIn(bool zeroForOne, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96)
        external
        onlyOwner
        nonReentrant
        returns (uint256 amountOut)
    {
        address tokenIn = zeroForOne ? token0 : token1;
        address tokenOut = zeroForOne ? token1 : token0;
        _approveIfNeeded(tokenIn, address(swapRouter), amountIn);
        IDragonSwapRouter.ExactInputSingleParams memory p = IDragonSwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        amountOut = swapRouter.exactInputSingle(p);
        emit TokensSwapped(tokenIn, tokenOut, amountIn, amountOut);
    }

    // -----------------------
    // Helpers
    // -----------------------
    /**
     * @dev Approves `spender` to spend `token` if the current allowance is insufficient.
     *      Resets to zero first to be compatible with non-standard ERC20s.
     */
    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        if (amount == 0) return;
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).approve(spender, 0);
            IERC20(token).approve(spender, type(uint256).max);
        }
    }

    /**
     * @dev Floors `tick` to the nearest valid initialized tick according to `spacing`.
     */
    function _floorTick(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = tick - (tick % spacing);
        if (floored < TickMathLib.MIN_TICK) return TickMathLib.MIN_TICK;
        return floored;
    }

    /**
     * @dev Ceils `tick` to the nearest valid initialized tick according to `spacing`.
     */
    function _ceilTick(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 ceiled = tick % spacing == 0 ? tick : tick + (spacing - (tick % spacing));
        if (ceiled > TickMathLib.MAX_TICK) return TickMathLib.MAX_TICK;
        return ceiled;
    }

    /// @dev Returns Q96 price of token0 denominated in token1 based on current spot price.
    function _twapToken0PerToken1X96() internal view returns (uint256 priceX96) {
        (uint160 sqrtPriceX96,, , , , , ) = pool.slot0();
        // price0 per 1 = (sqrtP^2 / 2^192)
        uint256 ratioX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        priceX96 = ratioX192 >> 96; // Q96
    }

    /**
     * @dev Attempts to prepare `assets` amount of `token1` by:
     *      1) using idle `token1`, 2) removing proportional liquidity, and 3) swapping idle `token0`.
     *      Reverts if still insufficient after these steps.
     */
    function _prepareAssetsForWithdrawal(uint256 assets, uint256 shares) internal {
        // try to satisfy from idle token1 first
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        if (bal1 >= assets) {
            return;
        }

        // redeem proportional liquidity based on shares/totalSupply
        if (positionLiquidity > 0) {
            uint256 ts = totalSupply();
            if (ts > 0) {
                uint128 liqToRemove = uint128((uint256(positionLiquidity) * shares) / ts);
                if (liqToRemove > 0) {
                    IDragonNonfungiblePositionManager.DecreaseLiquidityParams memory d = IDragonNonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: positionTokenId,
                        liquidity: liqToRemove,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    });
                    positionManager.decreaseLiquidity(d);
                    // collect withdrawn tokens and any fees
                    IDragonNonfungiblePositionManager.CollectParams memory c = IDragonNonfungiblePositionManager.CollectParams({
                        tokenId: positionTokenId,
                        recipient: address(this),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    });
                    positionManager.collect(c);
                    positionLiquidity -= liqToRemove;
                }
            }
        }

        // Swap token0 -> token1 to cover shortfall if any
        bal1 = IERC20(token1).balanceOf(address(this));
        if (bal1 < assets) {
            uint256 bal0 = IERC20(token0).balanceOf(address(this));
            if (bal0 > 0) {
                _approveIfNeeded(token0, address(swapRouter), bal0);
                IDragonSwapRouter.ExactInputSingleParams memory p = IDragonSwapRouter.ExactInputSingleParams({
                    tokenIn: token0,
                    tokenOut: token1,
                    fee: fee,
                    recipient: address(this),
                    amountIn: bal0,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });
                swapRouter.exactInputSingle(p);
            }
        }

        require(IERC20(token1).balanceOf(address(this)) >= assets, "Insufficient token1 assets for withdrawal");
    }
}


