pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INXDStakingVault {
    function deposit(uint256 _pid, uint256 _amount) external;
    function add(uint256 _allocPoint, IERC20 _token, bool _withUpdate, bool _withdrawable) external;
    function pendingRewards() external view returns (uint256);
}
