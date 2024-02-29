pragma solidity ^0.8.13;

interface IV3Oracle {
    function getHumanQuote(
        address uniswapV3Pool,
        uint32 secondsAgo,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) external view returns (uint256 quoteAmount);
}
