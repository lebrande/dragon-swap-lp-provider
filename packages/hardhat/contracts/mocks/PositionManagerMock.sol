// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PositionManagerMock {
    address public immutable token0;
    address public immutable token1;

    uint256 public nextId = 1;
    uint256 public lastId;
    uint128 public liquidity;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

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

    function mint(MintParams calldata params) external returns (uint256 tokenId, uint128 liq, uint256 amount0, uint256 amount1) {
        require(params.recipient == address(this) || params.recipient == msg.sender, "recp");
        if (params.amount0Desired > 0) IERC20(token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        if (params.amount1Desired > 0) IERC20(token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        tokenId = nextId++;
        lastId = tokenId;
        liq = uint128(params.amount0Desired + params.amount1Desired);
        liquidity += liq;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params) external returns (uint128 liq, uint256 used0, uint256 used1) {
        if (params.amount0Desired > 0) IERC20(token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        if (params.amount1Desired > 0) IERC20(token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        used0 = params.amount0Desired; used1 = params.amount1Desired;
        liq = uint128(used0 + used1);
        liquidity += liq;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        liquidity -= params.liquidity;
        amount0 = params.amount0Min; amount1 = params.amount1Min; // mock
    }

    function collect(CollectParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        // no-op mock, nothing to send out
        amount0 = 0; amount1 = 0;
    }
}


