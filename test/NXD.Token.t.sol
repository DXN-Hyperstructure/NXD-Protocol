// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/NXDProtocol.sol";
import "../src/NXDERC20.sol";
import "../src/NXDStakingVault.sol";
import "../src/dbxen/MockToken.sol";
import "../src/dbxen/DBXen.sol";
import "../src/dbxen/DBXenViews.sol";
import "../src/dbxen/DBXenERC20.sol";
import "../src/dbxen/mocks/XENCryptoMockMint.sol";
import "./NXD.Shared.t.sol";

contract NXDTokenTest is NXDShared {
    function setUp() public {}

    function testRevertWhenUnauthorizedMint() public {
        uint256 amountToMint = 1000;
        uint256 bobBalanceBefore = nxd.balanceOf(bob);
        vm.expectRevert(NXDERC20.Unauthorized.selector);
        nxd.mint(bob, amountToMint);
        assertEq(nxd.balanceOf(bob), bobBalanceBefore, "balance should not change");
    }

    function testRevertWhenUnauthorizedSetUniswapPair() public {
        address uniswapV2PairBefore = address(nxd.uniswapV2Pair());
        vm.expectRevert(NXDERC20.Unauthorized.selector);
        nxd.setUniswapV2Pair(address(0x0));
        assertEq(address(nxd.uniswapV2Pair()), uniswapV2PairBefore, "uniswap pair should not change");
    }

    function testRevertWhenUnauthorizedSetV2Oracle() public {
        address v2OracleBefore = address(nxd.v2Oracle());
        vm.expectRevert(NXDERC20.Unauthorized.selector);
        nxd.setV2Oracle(address(0x0));
        assertEq(address(nxd.v2Oracle()), v2OracleBefore, "uniswap pair should not change");
    }

    function testRevertWhenUnauthorizedUpdateTaxWhitelist() public {
        (bool sender, bool recipient) = nxd.isExcludedFromTax(address(nxdProtocol));
        vm.expectRevert(NXDERC20.Unauthorized.selector);
        nxd.updateTaxWhitelist(address(nxdProtocol), false, false);
    }

    function testRevertWhenSetGovernanceUnauthorised() public {
        vm.expectRevert(NXDERC20.Unauthorized.selector);
        nxd.setGovernance(address(0x0));
    }

    function testSetGovernance() public {
        address newGovernance = address(0x1);
        address currentGovernance = nxd.governance();
        vm.prank(currentGovernance);
        nxd.setGovernance(newGovernance);
        assertEq(nxd.governance(), newGovernance, "governance should be updated");
    }

    function testAmountsAfterTaxWhenPairRecipient() public {
        uint256 amount = 1000;

        uint256 expectedTaxAmount = (amount * nxd.SELL_TAX_X100()) / 10000;
        uint256 expectedAmountAfterTax = amount - expectedTaxAmount;

        address uniswapV2Pair = address(nxd.uniswapV2Pair());

        (uint256 amountAfterTax, uint256 taxAmount) = nxd.getAmountsAfterTax(bob, uniswapV2Pair, amount);

        assertEq(amountAfterTax, amount - taxAmount, "amount after tax should be amount - taxAmount");
        assertEq(taxAmount, expectedTaxAmount, "taxAmount should match");
        assertEq(expectedAmountAfterTax, amountAfterTax, "amountAfterTax should match");
    }

    function testFuzz_AmountsAfterTaxWhenPairRecipient(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 1000);

        uint256 expectedTaxAmount = (amount * nxd.SELL_TAX_X100()) / 10000;
        uint256 expectedAmountAfterTax = amount - expectedTaxAmount;

        address uniswapV2Pair = address(nxd.uniswapV2Pair());

        (uint256 amountAfterTax, uint256 taxAmount) = nxd.getAmountsAfterTax(bob, uniswapV2Pair, amount);

        assertEq(amountAfterTax, amount - taxAmount, "amount after tax should be amount - taxAmount");
        assertEq(taxAmount, expectedTaxAmount, "taxAmount should match");
        assertEq(expectedAmountAfterTax, amountAfterTax, "amountAfterTax should match");
    }

    uint256 devFeeBalanceBefore;
    uint256 expectedDevFeeAmount;

    function testSellNXD() public {
        uint256 amount = 1000 ether;
        uint256 expectedTaxAmount = (amount * nxd.SELL_TAX_X100()) / 10000;
        uint256 expectedAmountAfterTax = amount - expectedTaxAmount;

        address[] memory path = new address[](2);
        path[0] = address(nxd);
        path[1] = address(MAINNET_DXN);

        IUniswapV2Pair uniswapV2Pair = nxd.uniswapV2Pair();
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 1, true);
        (uint256 res0, uint256 res1,) = uniswapV2Pair.getReserves();
        (uint256 resNXD, uint256 resDXN) = uniswapV2Pair.token0() == address(nxd) ? (res0, res1) : (res1, res0);
        console.log("testSellNXD: resNXD before add liquidity test = ", resNXD);
        console.log("testSellNXD: resDXN before add liquidity test = ", resDXN);
        // We now have NXD
        uint256 bobDXNBalanceBeforeSwap = dxn.balanceOf(address(bob));

        devFeeBalanceBefore = nxd.balanceOf(devFeeTo);
        expectedDevFeeAmount = (expectedTaxAmount * 1000) / 10000;
        // Simulate tax behavior: swap and add liquidity
        uint256 sellNXDAmount = (expectedTaxAmount * 4000) / 10000; // 40% (2/5) of total tax amount, which is 1.5% buy and stake DXN + 0.5% buy DXN to add liq
        // tax sellNXDAmount
        uint256 dxnOutFromTaxSwap = UNISWAP_V2_ROUTER.getAmountsOut(sellNXDAmount, path)[1];
        console.log("testSellNXD expected sell nxd amount = ", sellNXDAmount);
        console.log("testSellNXD expected tax recipient received dxn = ", dxnOutFromTaxSwap);
        resNXD += sellNXDAmount;
        resDXN -= dxnOutFromTaxSwap;
        console.log("testSellNXD: resNXD after tax swap = ", resNXD);
        console.log("testSellNXD: resDXN after tax swap = ", resDXN);
        // ├─ [0] console::log("testSellNXD: resNXD after add liquidity test = ", 5040000000000000001000 [5.04e21]) [staticcall]
        // │   └─ ← ()
        // ├─ [0] console::log("testSellNXD: resDXN  after add liquidity test = ", 994055535080060567331 [9.94e20]) [staticcall]
        {
            uint256 remainingTax = expectedTaxAmount - sellNXDAmount; // 30%
            console.log("testSellNXD: remainingTax = ", remainingTax);
            uint256 burnAmount = (expectedTaxAmount * 4000) / 10000;
            console.log("testSellNXD: burnAmount = ", burnAmount);
            uint256 rate = (resNXD * 1e18) / resDXN;
            uint256 expectedDXNAmountToAddLiquidity = ((remainingTax - burnAmount - expectedDevFeeAmount) * 1e18) / rate;
            console.log("testSellNXD: expected to add NXD liq = ", remainingTax - burnAmount - expectedDevFeeAmount);
            console.log("testSellNXD: expectedDXNAmountToAddLiquidity = ", expectedDXNAmountToAddLiquidity);
            resNXD += remainingTax - burnAmount - expectedDevFeeAmount;
            resDXN += expectedDXNAmountToAddLiquidity;
        }
        console.log("testSellNXD: resNXD after add liquidity test = ", resNXD);
        console.log("testSellNXD: resDXN  after add liquidity test = ", resDXN);
        console.log("testSellNXD expectedAmountAfterTax = ", expectedAmountAfterTax);
        uint256 expectedSwapOutput = UNISWAP_V2_ROUTER.getAmountOut(expectedAmountAfterTax, resNXD, resDXN);
        console.log("testSellNXD expectedSwapOutput = ", expectedSwapOutput);
        nxd.approve(address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount, 0, path, address(bob), block.timestamp
        );
        // expected: NXD reserves: 994055535080060567331, 5040000000000000001000
        // actual: NXD reseves: 993477053058469646182 [9.934e20], 5037067015588235293914
        console.log("testSellNXD bob received %s DXN", dxn.balanceOf(address(bob)) - bobDXNBalanceBeforeSwap);
        assertEq(
            dxn.balanceOf(address(bob)),
            bobDXNBalanceBeforeSwap + expectedSwapOutput,
            "Bob DXN balance should increase by expected Amount"
        );
        assertEq(
            nxd.balanceOf(devFeeTo) - devFeeBalanceBefore,
            expectedDevFeeAmount,
            "Dev fee to should increase by expected amount"
        );
    }

    function testFuzz_SellNXD(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 1000); // ensure no overflow when calculating tax
        vm.assume(amount < type(uint256).max / nxdProtocol.currentRate()); // ensure no overflow when calculating tax
        vm.assume(amount >= 1 ether); // ensure amount is not too small. will cause UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT
        vm.assume(amount <= nxd.MAX_REWARDS_SUPPLY());

        uint256 expectedTaxAmount = (amount * nxd.SELL_TAX_X100()) / 10000;

        address[] memory path = new address[](2);
        path[0] = address(nxd);
        path[1] = address(MAINNET_DXN);

        IUniswapV2Pair uniswapV2Pair = nxd.uniswapV2Pair();

        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 1, true);
        (uint256 res0, uint256 res1,) = uniswapV2Pair.getReserves();

        // We now have NXD
        uint256 bobNXDBalanceBefore = nxd.balanceOf(bob);
        uint256 bobDXNBalanceBeforeSwap = dxn.balanceOf(address(bob));
        vm.assume(amount <= bobDXNBalanceBeforeSwap);
        devFeeBalanceBefore = nxd.balanceOf(devFeeTo);
        expectedDevFeeAmount = (expectedTaxAmount * 1000) / 10000;

        // Simulate tax behavior: swap and add liquidity. This modifies the pool reserves
        uint256 sellNXDAmount = (expectedTaxAmount * 4000) / 10000; // 70%
        uint256 dxnOutFromTaxSwap = UNISWAP_V2_ROUTER.getAmountsOut(sellNXDAmount, path)[1];

        (uint256 resNXD, uint256 resDXN) = uniswapV2Pair.token0() == address(nxd) ? (res0, res1) : (res1, res0);
        {
            uint256 remainingDXNBalance = dxnOutFromTaxSwap - ((dxnOutFromTaxSwap * 750000000000000000) / 1e18);
            resNXD += sellNXDAmount;
            resDXN -= dxnOutFromTaxSwap;
            uint256 remainingTax = expectedTaxAmount - sellNXDAmount; // 15%
            uint256 burnAmount = (expectedTaxAmount * 4000) / 10000;
            uint256 expectedDXNAmountToAddLiquidity =
                UNISWAP_V2_ROUTER.quote((remainingTax - burnAmount - expectedDevFeeAmount), resNXD, resDXN);
            expectedDXNAmountToAddLiquidity = expectedDXNAmountToAddLiquidity >= remainingDXNBalance
                ? remainingDXNBalance
                : expectedDXNAmountToAddLiquidity;
            resNXD += expectedDXNAmountToAddLiquidity == remainingDXNBalance
                ? UNISWAP_V2_ROUTER.quote(expectedDXNAmountToAddLiquidity, resDXN, resNXD)
                : remainingTax - burnAmount - expectedDevFeeAmount;
            resDXN += expectedDXNAmountToAddLiquidity;
        }

        uint256 expectedSwapOutput = UNISWAP_V2_ROUTER.getAmountOut(amount - expectedTaxAmount, resNXD, resDXN);

        nxd.approve(address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount, 0, path, address(bob), block.timestamp
        );

        assertEq(
            dxn.balanceOf(address(bob)),
            bobDXNBalanceBeforeSwap + expectedSwapOutput,
            "Bob DXN balance should increase by expected Amount"
        );
        assertEq(nxd.balanceOf(address(bob)), bobNXDBalanceBefore - amount, "Bob NXD balance should decrease by amount");
        assertEq(
            nxd.balanceOf(devFeeTo) - devFeeBalanceBefore,
            expectedDevFeeAmount,
            "Dev fee to should increase by expected amount"
        );
    }

    function testBuyNXD() public {
        uint256 dxnToSell = 1000 ether;
        uint256 bobNXDBalanceBefore = nxd.balanceOf(address(bob));
        uint256 bobDXNBalanceBefore = dxn.balanceOf(address(bob));

        address[] memory path = new address[](2);
        path[0] = address(MAINNET_DXN);
        path[1] = address(nxd);

        IUniswapV2Pair uniswapV2Pair = nxd.uniswapV2Pair();
        (uint256 res0, uint256 res1,) = uniswapV2Pair.getReserves();
        (address token0) = uniswapV2Pair.token0();

        (uint256 resNXD, uint256 resDXN) = token0 == address(nxd) ? (res0, res1) : (res1, res0);

        uint256 expectedSwapOutput = UNISWAP_V2_ROUTER.getAmountOut(dxnToSell, resDXN, resNXD);

        vm.startPrank(bob);
        dxn.approve(address(UNISWAP_V2_ROUTER), dxnToSell);
        UNISWAP_V2_ROUTER.swapExactTokensForTokens(dxnToSell, 0, path, address(bob), block.timestamp);

        assertEq(
            nxd.balanceOf(address(bob)),
            expectedSwapOutput + bobNXDBalanceBefore,
            "Bob NXD balance should increase by expected Amount"
        );
        assertEq(
            dxn.balanceOf(address(bob)),
            bobDXNBalanceBefore - dxnToSell,
            "Bob DXN balance should decrease by expected Amount"
        );
    }

    function testFuzz_BuyNXD(uint256 amount) public {
        uint256 bobNXDBalanceBefore = nxd.balanceOf(address(bob));
        uint256 bobDXNBalanceBefore = dxn.balanceOf(address(bob));
        vm.assume(amount <= bobDXNBalanceBefore); // ensure amount is not too large
        vm.assume(amount > 0);

        address[] memory path = new address[](2);
        path[0] = address(MAINNET_DXN);
        path[1] = address(nxd);

        IUniswapV2Pair uniswapV2Pair = nxd.uniswapV2Pair();
        (uint256 res0, uint256 res1,) = uniswapV2Pair.getReserves();
        (uint256 resNXD, uint256 resDXN) = uniswapV2Pair.token0() == address(nxd) ? (res0, res1) : (res1, res0);

        uint256 expectedSwapOutput = UNISWAP_V2_ROUTER.getAmountOut(amount, resDXN, resNXD);

        vm.startPrank(bob);
        dxn.approve(address(UNISWAP_V2_ROUTER), amount);
        UNISWAP_V2_ROUTER.swapExactTokensForTokens(amount, 0, path, address(bob), block.timestamp);

        assertEq(
            nxd.balanceOf(address(bob)),
            expectedSwapOutput + bobNXDBalanceBefore,
            "Bob NXD balance should increase by expected Amount"
        );
        assertEq(
            dxn.balanceOf(address(bob)),
            bobDXNBalanceBefore - amount,
            "Bob DXN balance should decrease by expected Amount"
        );
    }
}
