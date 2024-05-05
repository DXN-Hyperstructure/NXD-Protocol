pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INXDERC20 is IERC20 {
    function updateTaxWhitelist(address account, bool whenSender, bool whenRecipient) external;
    function governance() external view returns (address);
}
