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

 

contract DragonSwapLpProviderVault is ERC4626, Ownable, ReentrancyGuard {
    using TickMathLib for int24;

    // Immutable config
    address public immutable token0;
    address public immutable token1;
    IDragonV3Pool public immutable pool;
    IDragonNonfungiblePositionManager public immutable positionManager;
    IDragonSwapRouter public immutable swapRouter;
    uint24 public immutable fee; // 3000 = 0.3%

    // Manager role
    address public manager;

    // Position state
    uint256 public positionTokenId;
    uint128 public positionLiquidity;
    int24 public positionTickLower;
    int24 public positionTickUpper;

    // Valuation config
    uint32 public twapPeriod = 300; // seconds, as specified

    // Range width config (in basis points, around mid tick)
    uint16 public constant DEFAULT_RANGE_BPS = 1000; // +/-10%

    event ManagerUpdated(address indexed manager);
    event PositionCreated(uint256 indexed tokenId, uint128 liquidity, int24 tickLower, int24 tickUpper);
    event PositionIncreased(uint256 indexed tokenId, uint128 liquidityAdded, uint256 amount0, uint256 amount1);
    event PositionDecreased(uint256 indexed tokenId, uint128 liquidityRemoved, uint256 amount0, uint256 amount1);
    event RewardsCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event TokensSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    modifier onlyManager() {
        require(msg.sender == manager, "MANAGER");
        _;
    }

    constructor(
        address _assetToken1,
        address _token0,
        address _pool,
        address _positionManager,
        address _swapRouter,
        uint24 _fee,
        address _owner
    ) ERC20("DragonSwap USDC DEX LP", "DRGusdc") ERC4626(IERC20(_assetToken1)) Ownable(_owner) {
        require(_assetToken1 != address(0) && _token0 != address(0), "TOKENS");
        require(_pool != address(0) && _positionManager != address(0) && _swapRouter != address(0), "ADDRESSES");
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
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerUpdated(_manager);
    }

    function setTwapPeriod(uint32 _period) external onlyOwner {
        require(_period >= 60 && _period <= 86400, "PERIOD");
        twapPeriod = _period;
    }

    // -----------------------
    // ERC4626 overrides
    // -----------------------
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
    function createPosition(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyManager
        nonReentrant
        returns (uint256 tokenId, uint128 liquidity)
    {
        require(positionTokenId == 0, "EXISTS");

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

    function modifyPositionIncrease(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyManager
        nonReentrant
        returns (uint128 liquidity, uint256 used0, uint256 used1)
    {
        require(positionTokenId != 0, "NO_POS");
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

    function modifyPositionDecrease(uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
        external
        onlyManager
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(positionTokenId != 0, "NO_POS");
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

    function collectRewards() external onlyManager nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(positionTokenId != 0, "NO_POS");
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
    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        if (amount == 0) return;
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).approve(spender, 0);
            IERC20(token).approve(spender, type(uint256).max);
        }
    }

    function _floorTick(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = tick - (tick % spacing);
        if (floored < TickMathLib.MIN_TICK) return TickMathLib.MIN_TICK;
        return floored;
    }

    function _ceilTick(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 ceiled = tick % spacing == 0 ? tick : tick + (spacing - (tick % spacing));
        if (ceiled > TickMathLib.MAX_TICK) return TickMathLib.MAX_TICK;
        return ceiled;
    }

    // returns Q96 price of token0 denominated in token1 based on current spot price
    function _twapToken0PerToken1X96() internal view returns (uint256 priceX96) {
        (uint160 sqrtPriceX96,, , , , , ) = pool.slot0();
        // price0 per 1 = (sqrtP^2 / 2^192)
        uint256 ratioX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        priceX96 = ratioX192 >> 96; // Q96
    }

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

        require(IERC20(token1).balanceOf(address(this)) >= assets, "INSUFFICIENT_ASSETS");
    }
}


