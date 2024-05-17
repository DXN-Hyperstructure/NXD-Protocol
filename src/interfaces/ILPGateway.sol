pragma solidity ^0.8.13;

interface ILPGateway {
    function addLiquidity(
        address tokenB,
        uint256 amountNXDDesired,
        uint256 amountBDesired,
        uint256 amountNXDMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}
