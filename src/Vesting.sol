pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract Vesting {
    error NotValidToken();
    error AlreadySet();
    error Owner();

    uint256 public constant VESTING_DURATION_SECS = 90 days;

    struct VestingSchedule {
        uint256 amount;
        uint256 startTimestamp;
    }

    mapping(address => VestingSchedule) public tokenAmountToVest;
    mapping(address => uint256) public claimed;

    IERC20 public token;

    address owner;

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev     Set the token to be vested.
     * @param   tokenAddress  The address of the token to be vested.
     */
    function setToken(address tokenAddress) public {
        if (msg.sender != owner) {
            revert Owner();
        }
        if (address(tokenAddress) == address(0)) {
            revert NotValidToken();
        }
        if (address(token) != address(0)) {
            revert AlreadySet();
        }
        token = IERC20(tokenAddress);
    }

    function setVesting(address user, uint256 amount) public {
        if (msg.sender != owner) {
            revert Owner();
        }
        tokenAmountToVest[user] = VestingSchedule(amount, block.timestamp);
    }

    function claimable(address user) public view returns (uint256) {
        VestingSchedule memory vestingSchedule = tokenAmountToVest[user];
        if (vestingSchedule.amount == 0) {
            return 0;
        }
        uint256 elapsed = block.timestamp - vestingSchedule.startTimestamp;
        if (elapsed == 0) {
            return 0;
        }
        console.log("Vesting: claimable: elapsed = ", elapsed);
        if (elapsed >= VESTING_DURATION_SECS) {
            return vestingSchedule.amount - claimed[user];
        }
        return (vestingSchedule.amount * elapsed) / VESTING_DURATION_SECS - claimed[user];
    }

    function claim() public {
        uint256 claimableAmount = claimable(msg.sender);
        if (claimableAmount > 0) {
            claimed[msg.sender] += claimableAmount;
            // transfer to msg.sender
            token.transfer(msg.sender, claimableAmount);
        }
    }
}
