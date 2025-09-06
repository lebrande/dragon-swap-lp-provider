// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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


