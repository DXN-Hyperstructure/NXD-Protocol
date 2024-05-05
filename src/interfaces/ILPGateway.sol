pragma solidity ^0.8.13;

interface ILPGateway {
    function addLiquidity(
        uint256 amountNXDDesired,
        uint256 amountDXNDesired,
        uint256 amountNXDMin,
        uint256 amountDXNMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}
