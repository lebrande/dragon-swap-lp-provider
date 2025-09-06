// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PoolMock {
    uint160 public sqrtPriceX96;
    int24 public tick;
    uint16 public observationIndex;
    uint16 public observationCardinality;
    uint16 public observationCardinalityNext;
    uint8 public feeProtocol;
    bool public unlocked;
    int24 public _tickSpacing = 60;

    constructor() {
        sqrtPriceX96 = 79228162514264337593543950336; // ~1.0 in Q96
        tick = 0;
        observationIndex = 0;
        observationCardinality = 1;
        observationCardinalityNext = 1;
        feeProtocol = 0;
        unlocked = true;
    }

    function setPriceTick(uint160 _sqrtPriceX96, int24 _tick) external {
        sqrtPriceX96 = _sqrtPriceX96;
        tick = _tick;
    }

    function setTickSpacing(int24 spacing) external {
        _tickSpacing = spacing;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, tick, observationIndex, observationCardinality, observationCardinalityNext, feeProtocol, unlocked);
    }

    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory, uint160[] memory) {
        int56[] memory tickCumulatives = new int56[](secondsAgos.length);
        uint160[] memory liqCum = new uint160[](secondsAgos.length);
        // simplistic: cumulative tick = tick * t
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            tickCumulatives[i] = int56(int256(tick)) * int56(uint56(secondsAgos[i]));
            liqCum[i] = 0;
        }
        return (tickCumulatives, liqCum);
    }

    function tickSpacing() external view returns (int24) {
        return _tickSpacing;
    }
}


