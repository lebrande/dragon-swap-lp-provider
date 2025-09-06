// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RouterMock {
    address public immutable token0;
    address public immutable token1;

    constructor(address _token0, address _token1) {
        token0 = _token0; token1 = _token1;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata p) external returns (uint256 amountOut) {
        require(p.recipient == address(this), "rec");
        require(p.tokenIn == token0 || p.tokenIn == token1, "tok");
        require(p.tokenOut == token0 || p.tokenOut == token1, "tok2");
        IERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        // mock 1:1 swap
        IERC20(p.tokenOut).transfer(p.recipient, p.amountIn);
        return p.amountIn;
    }
}


