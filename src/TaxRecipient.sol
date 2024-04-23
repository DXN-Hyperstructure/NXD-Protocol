pragma solidity >=0.8.0;

import "./interfaces/INXDProtocol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract TaxRecipient {
    error OnlyNXD();

    IERC20 public immutable nxd;
    address public immutable protocol;
    IERC20 public constant dxn = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F); // DXN token
    IUniswapV2Router02 public UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Pair public uniswapV2Pair;

    constructor(address _protocol) {
        nxd = IERC20(msg.sender);
        protocol = _protocol;
    }

    function setUniswapV2Pair(address _uniswapV2Pair) external {
        if (msg.sender != address(nxd)) {
            revert OnlyNXD();
        }
        uniswapV2Pair = IUniswapV2Pair(_uniswapV2Pair);
    }

    /**
     * @dev     Handle tax from NXD protocol. Stakes 80% of received DXN and adds liquidity with the rest.
     */
    function handleTax() external {
        if (msg.sender != address(nxd)) {
            revert OnlyNXD();
        }
        uint256 ourDXNBalance = dxn.balanceOf(address(this));
        uint256 ratio = 750000000000000000; // Stake 1.5% of all our DXN balance (1.5*1e18 /2)
        uint256 dxnToStake = (ourDXNBalance * ratio) / 1e18;
        // Stake 8% of total tax after swap to DXN
        dxn.approve(protocol, dxnToStake);
        INXDProtocol(protocol).depositNoMint(dxnToStake);

        // Add liquidity with remaining NXD and DXN
        ourDXNBalance = dxn.balanceOf(address(this));

        // Approve tokens
        dxn.approve(address(UNISWAP_V2_ROUTER), ourDXNBalance);
        nxd.approve(address(UNISWAP_V2_ROUTER), nxd.balanceOf(address(this)));
        // Add liquidity
        UNISWAP_V2_ROUTER.addLiquidity(
            address(nxd),
            address(dxn),
            nxd.balanceOf(address(this)),
            ourDXNBalance,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
