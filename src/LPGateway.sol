pragma solidity >=0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract LPGateway {
    IERC20 public constant dxn = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F);
    IERC20 public constant nxd = IERC20(0x70536D44820fE3ddd4A2e3eEdbC937b8B9D566C7);

    IUniswapV2Router02 public UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IUniswapV2Pair public dxnNXDPair = IUniswapV2Pair(0x98134CDE70ff7280bb4b9f4eBa2154009f2C13aC);

    function addLiquidity(
        uint256 amountNXDDesired,
        uint256 amountDXNDesired,
        uint256 amountNXDMin,
        uint256 amountDXNMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        nxd.transferFrom(msg.sender, address(this), amountNXDDesired);
        dxn.transferFrom(msg.sender, address(this), amountDXNDesired);

        nxd.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
        dxn.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

        (amountA, amountB, liquidity) = UNISWAP_V2_ROUTER.addLiquidity(
            address(nxd), address(dxn), amountNXDDesired, amountDXNDesired, amountNXDMin, amountDXNMin, to, deadline
        );

        if (amountNXDDesired > amountA) {
            nxd.transfer(msg.sender, amountNXDDesired - amountA);
        }
        if (amountDXNDesired > amountB) {
            dxn.transfer(msg.sender, amountDXNDesired - amountB);
        }
    }

    function removeLiquidity(
        uint256 liquidity,
        uint256 amountNXDMin,
        uint256 amountDXNMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountNXD, uint256 amountDXN) {
        dxnNXDPair.transferFrom(msg.sender, address(this), liquidity);
        dxnNXDPair.approve(address(UNISWAP_V2_ROUTER), liquidity);

        (amountNXD, amountDXN) = UNISWAP_V2_ROUTER.removeLiquidity(
            address(nxd), address(dxn), liquidity, amountNXDMin, amountDXNMin, to, deadline
        );
    }
}
