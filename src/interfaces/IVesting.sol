pragma solidity ^0.8.13;

interface IVesting {
    function setToken(address tokenAddress) external;

    function setVesting(address user, uint256 amount) external;
}
