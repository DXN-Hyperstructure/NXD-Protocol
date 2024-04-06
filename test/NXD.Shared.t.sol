pragma solidity >=0.8.0;

import "../src/dbxen/DBXenViews.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/NXDStakingVault.sol";
import "../src/NXDERC20.sol";
import "../src/NXDProtocol.sol";
import "../src/Vesting.sol";
import "../src/dbxen/DBXen.sol";
import "../src/dbxen/DBXenERC20.sol";
import "../src/dbxen/MockToken.sol";
import "forge-std/Test.sol";

import "../src/V3Oracle.sol";
import "../src/V2Oracle.sol";
import "@uniswap/v3-periphery/contracts/SwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/NonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../src/dbxen/mocks/XENCryptoMockMint.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

abstract contract NXDShared is Test {
    DBXenERC20 public dxn;
    uint256 startTime = 1706135898003;
    uint256 public endTime = startTime + 14 days;
    uint256 initialRate = 1 ether; // starts 1:1 DXN:NXD (1 DXN = 1 NXD)
    uint256 finalRate = 0.5 ether; //  ends 1:0.5 DXN:NXD (1 DXN = 0.5 NXD)
    uint256 public constant decreasePerSecond = 413359788359788359788359788360;

    uint256 internal bobPrivateKey;
    uint256 internal alicePk;
    uint256 internal charliePk;

    address internal bob;
    address internal alice;
    address internal charlie;

    XENCryptoMockMint public xen;
    DBXen public dbxen;
    DBXenViews dbxenViews;

    NXDProtocol public nxdProtocol;
    NXDERC20 public nxd;
    NXDStakingVault public nxdStakingVault;

    uint256 public constant REFERRAL_CODE_1 = 1;
    uint256 public constant REFERRAL_CODE_2 = 2;

    uint256 public constant REFERRER_BONUS = 500; // 5% bonus for referring user
    uint256 public constant REFERRAL_BONUS = 1000; // 10% bonus for referred user

    uint256 public constant NXD_MAX_REWARDS_SUPPLY = 730000 ether;

    UniswapV3Factory public uniswapV3Factory;
    MockToken public WETH = new MockToken(10000000000000e18, "WETH", "WETH", 18);
    UniswapV3Pool public dxnETHPool;
    V3Oracle public v3Oracle;
    SwapRouter public swapRouter;
    NonfungiblePositionManager public nonfungiblePositionManager;
    // LiquidityExamples public liquidityExamples;
    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    IERC20 MAINNET_DXN = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F); // DXN token
    IUniswapV2Router02 public UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    V2Oracle public v2Oracle;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public UNISWAP_V2_FACTORY = (0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    address public DEADBEEF = (0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF);

    IUniswapV2PairLocal public nxdDXNPair;

    uint256 public initialLiquiditySupply;

    uint256 public constant NXD_DEV_REWARDS_SUPPLY = 15000 ether; // 15,000 NXD
    uint256 public constant NXD_INITIAL_LP_SUPPLY = 5000 ether; //  5,000 NXD for initial supply for  NXD/DXN LP creation
    uint256 public constant INITIAL_NXD_SUPPLY = NXD_DEV_REWARDS_SUPPLY + NXD_INITIAL_LP_SUPPLY; //
    address public devRewardsRecepient1;
    address public devRewardsRecepient2;
    address public devRewardsRecepient3;

    address public devFeeTo;

    Vesting public nxdVesting;

    function spoofBalance(address token, address account, uint256 balance) public {
        vm.record();
        IERC20(token).balanceOf(account);
        (bytes32[] memory reads,) = vm.accesses(token);
        vm.store(token, reads[0], bytes32(uint256(balance)));
    }

    constructor() {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        bobPrivateKey = 0xa11ce;
        alicePk = 0xabc123;
        charliePk = 0xdef456;

        uint256 devRewardsRecepient1Pk = 1;
        uint256 devRewardsRecepient2Pk = 2;
        uint256 devRewardsRecepient3Pk = 3;

        bob = vm.addr(bobPrivateKey);
        alice = vm.addr(alicePk);
        charlie = vm.addr(charliePk);

        devFeeTo = vm.addr(44);

        devRewardsRecepient1 = vm.addr(devRewardsRecepient1Pk);
        devRewardsRecepient2 = vm.addr(devRewardsRecepient2Pk);
        devRewardsRecepient3 = vm.addr(devRewardsRecepient3Pk);

        uniswapV3Factory = new UniswapV3Factory();

        WETH.mint(bob, 1000000000 ether);
        WETH.mint(alice, 1000000000 ether);
        WETH.mint(charlie, 1000000000 ether);

        xen = new XENCryptoMockMint();
        xen.transfer(bob, 300000000000 ether);
        xen.transfer(alice, 300000000000 ether);
        xen.transfer(charlie, 300000000000 ether);
        vm.warp(startTime);

        dbxen = new DBXen(address(0), address(xen));
        dbxenViews = new DBXenViews(dbxen);

        dxn = dbxen.dxn();
        // dxn.mint(bob, 10000000 ether);
        // dxn.mint(alice, 10000000 ether);

        vm.label(address(dxn), "DXN");

        swapRouter = new SwapRouter(address(uniswapV3Factory), address(WETH));
        v3Oracle = new V3Oracle();

        vm.startPrank(bob);
        nxdVesting = new Vesting();

        nxdProtocol = new NXDProtocol(
            INITIAL_NXD_SUPPLY,
            address(dbxen),
            address(dbxenViews),
            address(v3Oracle),
            bob,
            address(nxdVesting),
            devFeeTo
        );
        nxd = nxdProtocol.nxd();

        nxdStakingVault = nxdProtocol.nxdStakingVault();

        nonfungiblePositionManager =
            new NonfungiblePositionManager(address(uniswapV3Factory), address(WETH), address(0));
        dxnETHPool = UniswapV3Pool(uniswapV3Factory.createPool(address(dxn), address(WETH), 3000));
        // liquidityExamples = new LiquidityExamples(address(nonfungiblePositionManager));
        dxnETHPool.initialize(TickMath.getSqrtRatioAtTick(207240));

        // vm.startPrank(bob);
        // dxn.approve(address(liquidityExamples), 10000 ether);
        // WETH.approve(address(liquidityExamples), 10000 ether);
        // liquidityExamples.mintNewPosition(address(dxn), address(WETH), 10000 ether, 100 ether);
        // console.log("dxnETHPool", address(dxnETHPool));
        // vm.stopPrank();
        // (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = v3Oracle.consult(address(dxnETHPool), 3000);
        // console.log("v3Oracle arithmeticMeanTick", arithmeticMeanTick);
        // console.log("v3Oracle harmonicMeanLiquidity", harmonicMeanLiquidity);
        spoofBalance(address(dxn), bob, 100000000 ether);
        spoofBalance(address(dxn), alice, 100000000 ether);
        spoofBalance(address(dxn), charlie, 100000000 ether);

        // MAINNET_DXN.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
        // nxd.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
        // UNISWAP_V2_ROUTER.addLiquidity(
        //     address(MAINNET_DXN), address(nxd), 1000 ether, 10000 ether, 0, 0, address(this), block.timestamp
        // );

        nxd.approve(address(nxdProtocol), type(uint256).max);
        MAINNET_DXN.approve(address(nxdProtocol), type(uint256).max);
        initialLiquiditySupply =
            nxdProtocol.createPool(NXD_INITIAL_LP_SUPPLY, 1000 ether, address(this), block.timestamp);

        // Deploy vesting
        nxd.transfer(address(nxdVesting), NXD_DEV_REWARDS_SUPPLY);
        nxdVesting.setToken(address(nxd));
        nxdVesting.setVesting(devRewardsRecepient1, 5000 ether);
        nxdVesting.setVesting(devRewardsRecepient2, 5000 ether);
        nxdVesting.setVesting(devRewardsRecepient3, 5000 ether);

        vm.stopPrank();

        nxdDXNPair = IUniswapV2PairLocal(
            IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(address(MAINNET_DXN), address(nxd))
        );

        v2Oracle = nxdProtocol.v2Oracle();

        vm.label(address(xen), "XEN");
        vm.label(address(bob), "BOB");
        vm.label(address(alice), "Alice");
        vm.label(address(charlie), "CHARLIE");

        vm.label(address(nxd), "NXD");
        vm.label(address(dxn), "DNX Token");
        vm.label(address(MAINNET_DXN), "MAINNET DXN Token");
        vm.label(address(dbxen), "DBXen");
        vm.label(address(nxdProtocol), "nxdProtocol");
        vm.label(address(nxdStakingVault), "NXD Staking Vault");

        vm.label(address(nxd.taxRecipient()), "TAX RECIPIENT");
    }
}
