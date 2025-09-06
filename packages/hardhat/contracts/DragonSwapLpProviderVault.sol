// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal Uniswap V3 pool interface (DragonSwap compatible)
interface IDragonV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    function tickSpacing() external view returns (int24);
}

/// @notice Minimal NonfungiblePositionManager (DragonSwap compatible)
interface IDragonNonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

/// @notice Minimal SwapRouter (DragonSwap compatible)
interface IDragonSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

/// @notice Port of Uniswap V3 TickMath for solidity ^0.8
library TickMathLib {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739 + 1; // rounded up
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342 - 1; // rounded down

    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        int256 tick_ = int256(tick);
        require(tick_ >= MIN_TICK && tick_ <= MAX_TICK, "T");

        uint256 absTick = uint256(tick_ < 0 ? -tick_ : tick_);
        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick_ > 0) ratio = type(uint256).max / ratio;

        // round up to Q64.96
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, "R");
        uint256 ratio = uint256(sqrtPriceX96) << 32;

        uint256 r = ratio;
        uint256 msb = 0;
        unchecked {
            uint256 f;
            if (r >= 0x100000000000000000000000000000000) { r >>= 128; msb += 128; }
            if (r >= 0x10000000000000000) { r >>= 64; msb += 64; }
            if (r >= 0x100000000) { r >>= 32; msb += 32; }
            if (r >= 0x10000) { r >>= 16; msb += 16; }
            if (r >= 0x100) { r >>= 8; msb += 8; }
            if (r >= 0x10) { r >>= 4; msb += 4; }
            if (r >= 0x4) { r >>= 2; msb += 2; }
            if (r >= 0x2) { msb += 1; }

            int256 log_2 = (int256(msb) - 128) << 64;
            r = msb >= 128 ? ratio >> (msb - 127) : ratio << (127 - msb);
            f = r >> 128; r = (r * r) >> 127; uint256 f2 = r >> 128; log_2 |= int256(f2) << 63;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 62;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 61;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 60;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 59;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 58;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 57;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 56;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 55;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 54;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 53;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 52;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 51;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 50;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 49;
            r = (r * r) >> 127; f2 = r >> 128; log_2 |= int256(f2) << 48;

            int256 log_sqrt10001 = log_2 * 255738958999603826347141; // 128.128 number * ln(1.0001)
            int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
            int24 tickHigh = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);
            tick = tickLow == tickHigh ? tickLow : (getSqrtRatioAtTick(tickHigh) <= sqrtPriceX96 ? tickHigh : tickLow);
        }
    }
}

library LiquidityAmountsLib {
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = _getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = _getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = _getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = _getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

    function _getAmount0ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity) private pure returns (uint256 amount0) {
        uint256 intermediate = (uint256(liquidity) << 96) / (sqrtRatioBX96 - sqrtRatioAX96);
        amount0 = (intermediate * (sqrtRatioBX96 - sqrtRatioAX96)) / (uint256(sqrtRatioAX96) * uint256(sqrtRatioBX96));
    }

    function _getAmount1ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity) private pure returns (uint256 amount1) {
        amount1 = (uint256(liquidity) * (sqrtRatioBX96 - sqrtRatioAX96)) >> 96;
    }
}

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

        // Convert everything to token1 using TWAP price only if needed
        uint256 idle0In1;
        uint256 pos0In1;
        if (idle0 > 0 || pos0 > 0) {
            uint256 priceX96 = _twapToken0PerToken1X96(); // Q96
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
    function swapTokensExactIn(bool zeroForOne, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96, uint256 deadline)
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
            deadline: deadline,
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

    // returns Q96 price of token0 denominated in token1 based on TWAP tick
    function _twapToken0PerToken1X96() internal view returns (uint256 priceX96) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapPeriod;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        int24 avgTick = int24(delta / int56(uint56(twapPeriod)));
        if (delta < 0 && (delta % int56(uint56(twapPeriod)) != 0)) avgTick--;
        uint160 sqrtPriceX96 = TickMathLib.getSqrtRatioAtTick(avgTick);
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
                    deadline: block.timestamp,
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


