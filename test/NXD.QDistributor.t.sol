// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

// import "./NXD.Shared.t.sol";
import "../src/QDistributor.sol";
import "../src/interfaces/INXDStakingVault.sol";
import "../src/LPGateway.sol";
import "../src/interfaces/INXDERC20.sol";
import "../src/interfaces/IV3Oracle.sol";
import "../src/interfaces/INXDProtocol.sol";
import "forge-std/Test.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract QDistributorTest is Test {
    QDistributor public qDistributor;
    uint256 public vaultPercentage = 3334;
    uint256 public protocolPercentage = 3333;
    uint256 public lpPercentage = 3333;

    address public governance = address(bob);
    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public bob;

    INXDStakingVault public nxdStakingVault;
    INXDProtocol public nxdProtocol;
    IV3Oracle public v3Oracle;
    LPGateway public lpGateway;

    address public constant DXN_WETH_POOL = 0x7F808fD904FFA3eb6A6F259e6965Fb1466A05372;
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IERC20 public constant dxn = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F);
    INXDERC20 public constant nxd = INXDERC20(0x70536D44820fE3ddd4A2e3eEdbC937b8B9D566C7);

    IQuoterV2 public constant quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        uint256 bobPrivateKey = 0xa11ce;
        bob = vm.addr(bobPrivateKey);

        lpGateway = new LPGateway();
        vm.prank(nxd.governance());
        nxd.updateTaxWhitelist(address(lpGateway), true, true);
        vm.startPrank(governance);
        qDistributor = new QDistributor(address(lpGateway));
        nxdStakingVault = INXDStakingVault(qDistributor.nxdStakingVault());
        nxdProtocol = INXDProtocol(qDistributor.nxdProtocol());
        v3Oracle = IV3Oracle(qDistributor.v3Oracle());
        vm.stopPrank();
    }

    function testSetUp() public {
        assertEq(qDistributor.vaultPercentage(), vaultPercentage);
        assertEq(qDistributor.protocolPercentage(), protocolPercentage);
        assertEq(qDistributor.lpPercentage(), lpPercentage);
        assertEq(qDistributor.governance(), address(governance));
    }

    function testPendingAmounts() public {
        console.log("bob = ", bob);
        vm.startPrank(bob);
        vm.deal(bob, 1000 ether);
        payable(qDistributor).call{value: 1000 ether}("");
        uint256 expectedVaultAmount = 200 ether;
        uint256 expectedProtocolAmount = 0;
        uint256 expectedLpAmount = 800 ether;

        assertEq(qDistributor.pendingAmountVault(), expectedVaultAmount);
        assertEq(qDistributor.pendingAmountProtocol(), expectedProtocolAmount);
        assertEq(qDistributor.pendingAmountLP(), expectedLpAmount);
    }

    function testFuzz_PendingAmounts(uint256 amountToDistribute) public {
        vm.assume(amountToDistribute < type(uint256).max / 10000);
        uint256 totalAmount = amountToDistribute;

        uint256 expectedVaultAmount = (totalAmount * vaultPercentage) / 10000;
        uint256 expectedProtocolAmount = (totalAmount * protocolPercentage) / 10000;
        uint256 expectedLpAmount = (totalAmount * lpPercentage) / 10000;

        vm.startPrank(bob);
        vm.deal(bob, totalAmount);
        payable(qDistributor).call{value: totalAmount}("");

        assertEq(qDistributor.pendingAmountVault(), expectedVaultAmount);
        assertEq(qDistributor.pendingAmountProtocol(), expectedProtocolAmount);
        assertEq(qDistributor.pendingAmountLP(), expectedLpAmount);
    }

    function testSendToVault() public {
        vm.startPrank(bob);
        vm.deal(bob, 1000 ether);
        payable(qDistributor).call{value: 1000 ether}("");
        uint256 expectedVaultAmount = 200 ether;
        uint256 expectedProtocolAmount = 0;
        uint256 expectedLpAmount = 800 ether;

        vm.startPrank(bob);
        uint256 nxdStakingVaultBalanceBefore = address(nxdStakingVault).balance;
        console.log("nxdStakingVaultBalanceBefore = ", nxdStakingVaultBalanceBefore);
        uint256 pendingRewardsBefore = nxdStakingVault.pendingRewards();
        console.log("pendingRewardsBefore = ", pendingRewardsBefore);
        qDistributor.sendToVault();
        uint256 pendingRewardsAfter = nxdStakingVault.pendingRewards();
        console.log("pendingRewardsAfter = ", pendingRewardsAfter);

        assertEq(address(nxdStakingVault).balance - nxdStakingVaultBalanceBefore, expectedVaultAmount);
        assertEq(pendingRewardsAfter - pendingRewardsBefore, expectedVaultAmount);
    }

    function testFuzz_SendToVault(uint256 amountToDistribute) public {
        vm.assume(amountToDistribute < type(uint256).max / 10000);
        uint256 totalAmount = amountToDistribute;

        uint256 expectedVaultAmount = (totalAmount * vaultPercentage) / 10000;
        uint256 expectedProtocolAmount = (totalAmount * protocolPercentage) / 10000;
        uint256 expectedLpAmount = (totalAmount * lpPercentage) / 10000;

        vm.startPrank(bob);
        vm.deal(bob, totalAmount);
        payable(qDistributor).call{value: totalAmount}("");

        uint256 nxdStakingVaultBalanceBefore = address(nxdStakingVault).balance;
        uint256 pendingRewardsBefore = nxdStakingVault.pendingRewards();
        qDistributor.sendToVault();
        uint256 pendingRewardsAfter = nxdStakingVault.pendingRewards();
        uint256 balanceAfter = address(nxdStakingVault).balance;

        assertEq(balanceAfter - nxdStakingVaultBalanceBefore, expectedVaultAmount);
        assertEq(pendingRewardsAfter - pendingRewardsBefore, expectedVaultAmount);
    }

    function testSendToProtocol() public {
        vm.deal(bob, 1000 ether);
        uint256 _protocolPercentage = 4000;

        vm.prank(governance);
        qDistributor.setPercentages(4000, _protocolPercentage, 2000);
        uint256 ethAmt = 0.5 ether;
        payable(qDistributor).call{value: ethAmt}("");
        uint256 expectedProtocolAmount = (ethAmt * 4000) / 10000;

        uint256 expectedETHToStakingVault = (expectedProtocolAmount * 1500) / 10000; // 15%

        vm.startPrank(bob);

        uint256 totalDXNBurnedBefore = nxdProtocol.totalDXNBurned();
        uint256 pendingDXNToStakeBefore = nxdProtocol.pendingDXNToStake();
        uint256 totalNXDBurnedBefore = nxdProtocol.totalNXDBurned();
        uint256 totalETHToStakingVaultBefore = nxdProtocol.totalETHToStakingVault();

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: address(dxn),
            fee: 10000,
            amountIn: (expectedProtocolAmount * 8500) / 10000,
            sqrtPriceLimitX96: 0
        });
        (uint256 expectedDXNAfterSwap,,,) = quoter.quoteExactInputSingle(params);

        console.log("expectedDXNAfterSwap = ", expectedDXNAfterSwap);
        uint256 expectedDXNToBurn = (expectedDXNAfterSwap * 11111111) / 100000000;
        uint256 expectedDxnToSwapForNXD = (expectedDXNAfterSwap * 58823529) / 100000000;
        uint256 expectedPendingDXNToStake = expectedDXNAfterSwap - expectedDXNToBurn - expectedDxnToSwapForNXD;

        qDistributor.sendToProtocol(ethAmt);

        uint256 totalDXNBurnedAfter = nxdProtocol.totalDXNBurned();
        uint256 pendingDXNToStakeAfter = nxdProtocol.pendingDXNToStake();
        uint256 totalNXDBurnedAfter = nxdProtocol.totalNXDBurned();
        uint256 totalETHToStakingVaultAfter = nxdProtocol.totalETHToStakingVault();

        assertEq(totalDXNBurnedAfter - totalDXNBurnedBefore, expectedDXNToBurn, "DXN to burn");
        assertEq(pendingDXNToStakeAfter - pendingDXNToStakeBefore, expectedPendingDXNToStake, "Pending DXN to stake");
        assertEq(
            totalETHToStakingVaultAfter - totalETHToStakingVaultBefore,
            expectedETHToStakingVault,
            "ETH to staking vault"
        );
    }

    function testAddToLP() public {
        vm.startPrank(bob);
        vm.deal(bob, 1000 ether);
        payable(qDistributor).call{value: 1000 ether}("");
        uint256 expectedVaultAmount = 200 ether;
        uint256 expectedProtocolAmount = 0;
        uint256 expectedLpAmount = 800 ether;

        vm.startPrank(bob);
        uint256 amountToAdd = 1 ether;
        qDistributor.addLP(amountToAdd);
    }
}
