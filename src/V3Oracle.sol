pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libraries/OracleLibrary.sol";

contract V3Oracle {
    function getSqrtTwapX96(address uniswapV3Pool, uint32 secondsAgo) public view returns (uint160 sqrtPriceX96) {
        if (secondsAgo == 0) {
            // return the current price if secondsAgo == 0
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = secondsAgo; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives,) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 =
                TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(secondsAgo))));
        }
    }

    function getHumanQuote(
        address uniswapV3Pool,
        uint32 secondsAgo,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) external view returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = getSqrtTwapX96(uniswapV3Pool, secondsAgo);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
