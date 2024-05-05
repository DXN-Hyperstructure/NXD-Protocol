pragma solidity >=0.8.0;

import "./interfaces/IV3Oracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IV2Oracle.sol";
import "./interfaces/ILPGateway.sol";
import "forge-std/console.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract QDistributor {
    error GotNothing();

    event Received(
        address from, uint256 ethAmount, uint256 amountToVault, uint256 amountToProtocol, uint256 amountToLP
    );
    event SentToProtocol(uint256 amount);
    event SentToVault(uint256 amount);
    event AddedLP(uint256 amount);
    event UpdatedPercentages(uint256 vaultPercentage, uint256 protocolPercentage, uint256 lpPercentage);
    event UpdatedMaxSlippage(uint256 maxSlippageForETHDXNSwap, uint256 maxSlippageForDXNNXDSwap);
    event UpdatedLPGateway(address lpGateway);
    event UpdatedGovernance(address governance);

    uint256 public constant PERCENTAGE_DIVISOR = 10000;
    address public nxdStakingVault = 0xa1B56E42137D06280E34B3E1352d80Ac3BECAF79;
    address public nxdProtocol = 0xE05430D42842C7B757E5633D19ca65350E01aE11;

    uint256 public vaultPercentage;
    uint256 public protocolPercentage;
    uint256 public lpPercentage;

    uint256 public pendingAmountVault;
    uint256 public pendingAmountProtocol;
    uint256 public pendingAmountLP;

    address public governance;

    ISwapRouter public UNISWAP_V3_ROUTER = block.chainid == 11155111
        ? ISwapRouter(payable(0x3a71158eb1f7ec993510d4628402062CD919B665))
        : ISwapRouter(payable(0xE592427A0AEce92De3Edee1F18E0157C05861564));

    address public constant DXN_WETH_POOL = 0x7F808fD904FFA3eb6A6F259e6965Fb1466A05372;
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IERC20 public constant dxn = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F);
    IERC20 public constant nxd = IERC20(0x70536D44820fE3ddd4A2e3eEdbC937b8B9D566C7);

    IUniswapV2Router02 public UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IV3Oracle public constant v3Oracle = IV3Oracle(0x21c6e0427fb2bA0E827253f48241aAbDd8051eAa);
    IUniswapV2Pair nxdDXNPair = IUniswapV2Pair(0x98134CDE70ff7280bb4b9f4eBa2154009f2C13aC);
    IV2Oracle public v2Oracle = IV2Oracle(0x14D558267A97c7a61554d7F7b23a594781E04495);

    uint256 public maxSlippageForETHDXNSwap = 2500; // 25%
    uint256 public maxSlippageForDXNNXDSwap = 2500; // 25%

    ILPGateway public lpGateway;

    constructor(uint256 _vaultPercentage, uint256 _protocolPercentage, uint256 _lpPercentage, address _lpGateway) {
        governance = msg.sender;
        require(_vaultPercentage + _protocolPercentage + _lpPercentage == PERCENTAGE_DIVISOR, "Invalid percentages");
        vaultPercentage = _vaultPercentage;
        protocolPercentage = _protocolPercentage;
        lpPercentage = _lpPercentage;
        lpGateway = ILPGateway(_lpGateway);
    }

    function setLPGateway(address _lpGateway) public {
        require(msg.sender == governance, "Only governance can set LP Gateway");
        lpGateway = ILPGateway(_lpGateway);
        emit UpdatedLPGateway(_lpGateway);
    }

    function setMaxSlippageForSwap(uint256 _maxSlippageForETHDXNSwap, uint256 _maxSlippageForDXNNXDSwap) public {
        require(msg.sender == governance, "Only governance can set max slippage for swap");
        maxSlippageForETHDXNSwap = _maxSlippageForETHDXNSwap;
        maxSlippageForDXNNXDSwap = _maxSlippageForDXNNXDSwap;
        emit UpdatedMaxSlippage(_maxSlippageForETHDXNSwap, _maxSlippageForDXNNXDSwap);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "Only governance can set governance");
        governance = _governance;
        emit UpdatedGovernance(_governance);
    }

    function sendToVault() public {
        uint256 amount = pendingAmountVault;
        pendingAmountVault = 0;
        (bool sent,) = nxdStakingVault.call{value: amount}("");
        require(sent, "Failed to send to vault");
        emit SentToVault(amount);
    }

    function sendToProtocol(uint256 amount) public {
        if (amount > pendingAmountProtocol) {
            amount = pendingAmountProtocol;
        }
        pendingAmountProtocol -= amount;
        (bool sent,) = nxdProtocol.call{value: amount}("");
        require(sent, "Failed to send to protocol");
        emit SentToProtocol(amount);
    }

    function addLP(uint256 amount) public {
        if (amount > pendingAmountLP) {
            amount = pendingAmountLP;
        }
        pendingAmountLP -= amount;

        // Sell 50% of the ETH for DXN
        uint256 quote = v3Oracle.getHumanQuote(DXN_WETH_POOL, 5 minutes, 1 ether, WETH9, address(dxn));
        uint256 minOut = (amount * quote) / 1e18;
        // slippage tolerance
        minOut = (minOut * (10000 - maxSlippageForETHDXNSwap)) / 10000;
        UNISWAP_V3_ROUTER.exactInputSingle{value: amount}(
            ISwapRouter.ExactInputSingleParams(
                WETH9, address(dxn), 10000, address(this), block.timestamp, amount, minOut, 0
            )
        );

        uint256 dxnPriceInEth = (1e18 * 1 ether) / quote;
        uint256 dxnAmountToAdd = (amount / 2) * 1e18 / dxnPriceInEth;
        uint256 dxnToSwapForNXD = dxn.balanceOf(address(this)) - dxnAmountToAdd;

        if (v2Oracle.canUpdate()) {
            v2Oracle.update();
        }
        // Buy NXD with remaining DXN
        uint256 amountOutMin = v2Oracle.consult(address(dxn), dxnToSwapForNXD);
        // slippage tolerance
        amountOutMin = (amountOutMin * (10000 - maxSlippageForDXNNXDSwap)) / 10000;
        address[] memory path = new address[](2);
        path[0] = address(dxn);
        path[1] = address(nxd);

        dxn.approve(address(UNISWAP_V2_ROUTER), dxnToSwapForNXD);

        uint256[] memory amounts = UNISWAP_V2_ROUTER.swapExactTokensForTokens(
            dxnToSwapForNXD, amountOutMin, path, address(this), block.timestamp
        );
        if (amounts[1] == 0) {
            revert GotNothing();
        }

        dxn.approve(address(lpGateway), dxn.balanceOf(address(this)));
        nxd.approve(address(lpGateway), nxd.balanceOf(address(this)));

        lpGateway.addLiquidity(
            nxd.balanceOf(address(this)), dxn.balanceOf(address(this)), 0, 0, address(this), block.timestamp
        );

        emit AddedLP(amount);
    }

    function setPercentages(uint256 _vaultPercentage, uint256 _protocolPercentage, uint256 _lpPercentage) public {
        require(msg.sender == governance, "Only governance can set percentages");
        require(_vaultPercentage + _protocolPercentage + _lpPercentage == PERCENTAGE_DIVISOR, "Invalid percentages");
        vaultPercentage = _vaultPercentage;
        protocolPercentage = _protocolPercentage;
        lpPercentage = _lpPercentage;
        emit UpdatedPercentages(_vaultPercentage, _protocolPercentage, _lpPercentage);
    }

    receive() external payable {
        uint256 amount = address(this).balance;

        uint256 amountToVault = (amount * vaultPercentage) / PERCENTAGE_DIVISOR;
        uint256 amountToProtocol = (amount * protocolPercentage) / PERCENTAGE_DIVISOR;
        uint256 amountToLP = (amount * lpPercentage) / PERCENTAGE_DIVISOR;

        console.log("amountToVault = ", amountToVault);
        console.log("amountToProtocol = ", amountToProtocol);
        console.log("amountToLP = ", amountToLP);
        console.log("amountToVault + amountToProtocol + amountToLP = ", amountToVault + amountToProtocol + amountToLP);

        pendingAmountVault += amountToVault;
        pendingAmountProtocol += amountToProtocol;
        pendingAmountLP += amountToLP;
        emit Received(msg.sender, amount, amountToVault, amountToProtocol, amountToLP);
    }
}
