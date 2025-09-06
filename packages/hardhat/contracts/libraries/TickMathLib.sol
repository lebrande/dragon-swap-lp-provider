// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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


