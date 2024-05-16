pragma solidity >=0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract LPGateway {
    IERC20 public constant nxd = IERC20(0x70536D44820fE3ddd4A2e3eEdbC937b8B9D566C7);

    IUniswapV2Router02 public constant UNISWAP_V2_ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Factory public constant UNISWAP_V2_FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    function addLiquidity(
        address tokenB,
        uint256 amountNXDDesired,
        uint256 amountBDesired,
        uint256 amountNXDMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        nxd.transferFrom(msg.sender, address(this), amountNXDDesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        nxd.approve(address(UNISWAP_V2_ROUTER), amountNXDDesired);
        IERC20(tokenB).approve(address(UNISWAP_V2_ROUTER), amountBDesired);

        (amountA, amountB, liquidity) = UNISWAP_V2_ROUTER.addLiquidity(
            address(nxd), address(tokenB), amountNXDDesired, amountBDesired, amountNXDMin, amountBMin, to, deadline
        );

        if (amountNXDDesired > amountA) {
            nxd.transfer(msg.sender, amountNXDDesired - amountA);
        }
        if (amountBDesired > amountB) {
            IERC20(tokenB).transfer(msg.sender, amountBDesired - amountB);
        }
    }

    function removeLiquidity(
        address tokenB,
        uint256 liquidity,
        uint256 amountNXDMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountNXD, uint256 amountDXN) {
        address pair = UNISWAP_V2_FACTORY.getPair(address(nxd), tokenB);
        IERC20(pair).transferFrom(msg.sender, address(this), liquidity);
        IERC20(pair).approve(address(UNISWAP_V2_ROUTER), liquidity);

        (amountNXD, amountDXN) = UNISWAP_V2_ROUTER.removeLiquidity(
            address(nxd), address(tokenB), liquidity, amountNXDMin, amountBMin, to, deadline
        );
    }
}
