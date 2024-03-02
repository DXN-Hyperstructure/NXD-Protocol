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

    function testSync() public {
        address uniswapV2Pair = address(nxd.uniswapV2Pair());
        (bool isBurn, bool lastIsMint) = nxd.sync(uniswapV2Pair);
        assertEq(isBurn, false, "isBurn should be false");
        assertEq(isBurn, lastIsMint, "lastIsMint should be false");
        // add 1000 because initial liqudity locked by uniswap
        assertEq(nxd.lpSupplyOfPair(uniswapV2Pair), initialLiquiditySupply + 1000, "lpSupplyOfPair should match");
    }

    function testRevertWhenSignalRoguePairMainLP() public {
        address uniswapV2Pair = address(nxd.uniswapV2Pair());
        vm.expectRevert(NXDERC20.NoRemovalMainLP.selector);
        nxd.signalRoguePair(address(dxn), 0, true);
    }

    function testRevertWhenSignalRoguePairWhenOtherTokenZeroAddress() public {
        address uniswapV2Pair = address(nxd.uniswapV2Pair());
        vm.expectRevert(NXDERC20.NoRemovalZeroAddress.selector);
        nxd.signalRoguePair(address(0), 0, true);
    }

    function testRevertSignalRoguePairWhenPairDoesNotExist() public {
        address uniswapV2Pair = address(nxd.uniswapV2Pair());
        vm.expectRevert(NXDERC20.NoRemovalZeroAddress.selector);
        nxd.signalRoguePair(address(DEADBEEF), 0, true);
    }

    function testSignalRoguePair() public {
        vm.startPrank(bob);
        MockToken rogueToken = (new MockToken(10000 ether, "", "", 18));
        spoofBalance(address(nxd), bob, 10000 ether);

        rogueToken.approve(address(UNISWAP_V2_ROUTER), 1000 ether);
        nxd.approve(address(UNISWAP_V2_ROUTER), 1000 ether);

        uint256 expectedPairBalanceAfterTax = 1000 ether - ((1000 ether * nxd.SELL_TAX_X100()) / 10000);

        UNISWAP_V2_ROUTER.addLiquidity(
            address(nxd), address(rogueToken), 1000 ether, 1000 ether, 0, 0, address(bob), block.timestamp
        );
        address pairAddress = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(address(nxd), address(rogueToken));

        assertEq(
            nxd.balanceOf(pairAddress),
            expectedPairBalanceAfterTax,
            "pair balance should be 1000 ether after lp addition"
        );

        nxd.signalRoguePair(address(rogueToken), 0, true);

        assertEq(nxd.balanceOf(pairAddress), 0, "pair balance should be 0 after lp removal");
    }

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

        // Simulate tax behavior: swap and add liquidity
        uint256 sellNXDAmount = (expectedTaxAmount * 7000) / 10000; // 70% (80% to buy and stake DXN, 5% to buy DXN and add liquidity to NXD/DXN pair)
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
            uint256 burnAmount = (remainingTax * 666666666666666600) / 1e18;
            console.log("testSellNXD: burnAmount = ", burnAmount);
            uint256 rate = (resNXD * 1e18) / resDXN;
            uint256 expectedDXNAmountToAddLiquidity = ((remainingTax - burnAmount) * 1e18) / rate;
            console.log("testSellNXD: expected to add NXD liq = ", remainingTax - burnAmount);
            console.log("testSellNXD: expectedDXNAmountToAddLiquidity = ", expectedDXNAmountToAddLiquidity);
            resNXD += remainingTax - burnAmount;
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

        // Simulate tax behavior: swap and add liquidity. This modifies the pool reserves
        uint256 sellNXDAmount = (expectedTaxAmount * 7000) / 10000; // 70%
        uint256 dxnOutFromTaxSwap = UNISWAP_V2_ROUTER.getAmountsOut(sellNXDAmount, path)[1];

        (uint256 resNXD, uint256 resDXN) = uniswapV2Pair.token0() == address(nxd) ? (res0, res1) : (res1, res0);
        {
            uint256 remainingDXNBalance = dxnOutFromTaxSwap - ((dxnOutFromTaxSwap * 857142857142857100) / 1e18);
            resNXD += sellNXDAmount;
            resDXN -= dxnOutFromTaxSwap;
            uint256 remainingTax = expectedTaxAmount - sellNXDAmount; // 15%
            uint256 burnAmount = (remainingTax * 666666666666666600) / 1e18;
            uint256 expectedDXNAmountToAddLiquidity =
                UNISWAP_V2_ROUTER.quote((remainingTax - burnAmount), resNXD, resDXN);
            expectedDXNAmountToAddLiquidity = expectedDXNAmountToAddLiquidity >= remainingDXNBalance
                ? remainingDXNBalance
                : expectedDXNAmountToAddLiquidity;
            resNXD += expectedDXNAmountToAddLiquidity == remainingDXNBalance
                ? UNISWAP_V2_ROUTER.quote(expectedDXNAmountToAddLiquidity, resDXN, resNXD)
                : remainingTax - burnAmount;
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

    function testRevertWhenWithdrawLP() public {
        uint256 amount = 1000 ether;

        IUniswapV2Pair uniswapV2Pair = nxd.uniswapV2Pair();

        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 1, true);
        // We now have NXD

        (uint256 res0, uint256 res1,) = uniswapV2Pair.getReserves();
        uint256 dxnAmountToAdd = UNISWAP_V2_ROUTER.quote(amount, res1, res0);

        nxd.approve(address(UNISWAP_V2_ROUTER), amount);
        dxn.approve(address(UNISWAP_V2_ROUTER), dxnAmountToAdd);

        UNISWAP_V2_ROUTER.addLiquidity(
            address(nxd), address(MAINNET_DXN), amount, dxnAmountToAdd, 0, 0, address(bob), block.timestamp
        );
        uint256 bobNXDBalanceBeforeWithdrawLP = nxd.balanceOf(address(bob));
        uint256 bobDXNBalanceBeforeWithdrawLP = MAINNET_DXN.balanceOf(address(bob));

        uint256 bobLPBalance = nxdDXNPair.balanceOf(address(bob));

        nxdDXNPair.approve(address(UNISWAP_V2_ROUTER), bobLPBalance);

        vm.expectRevert("UniswapV2: TRANSFER_FAILED");
        UNISWAP_V2_ROUTER.removeLiquidity(
            address(nxd), address(MAINNET_DXN), bobLPBalance, 0, 0, address(this), block.timestamp
        );

        assertEq(dxn.balanceOf(address(bob)), bobDXNBalanceBeforeWithdrawLP, "Bob DXN balance should not change");

        assertEq(nxd.balanceOf(address(bob)), bobNXDBalanceBeforeWithdrawLP, "Bob NXD balance should not change");

        assertEq(nxdDXNPair.balanceOf(address(bob)), bobLPBalance, "Bob LP balance should not change");
    }

    function testFuzz_RevertWhenWithdrawLP(uint256 amount) public {
        vm.assume(amount < type(uint256).max / nxdProtocol.currentRate()); // ensure no overflow when calculating tax
        vm.assume(amount <= nxd.MAX_REWARDS_SUPPLY());
        vm.assume(amount >= 10000); // avoid UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED and zero values due to division by 10k
        vm.assume(amount > 0);

        IUniswapV2Pair uniswapV2Pair = nxd.uniswapV2Pair();

        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 1, true);
        // We now have NXD

        (uint256 res0, uint256 res1,) = uniswapV2Pair.getReserves();
        uint256 dxnAmountToAdd = UNISWAP_V2_ROUTER.quote(amount, res1, res0);

        nxd.approve(address(UNISWAP_V2_ROUTER), amount);
        dxn.approve(address(UNISWAP_V2_ROUTER), dxnAmountToAdd);

        UNISWAP_V2_ROUTER.addLiquidity(
            address(nxd), address(MAINNET_DXN), amount, dxnAmountToAdd, 0, 0, address(bob), block.timestamp
        );
        uint256 bobNXDBalanceBeforeWithdrawLP = nxd.balanceOf(address(bob));
        uint256 bobDXNBalanceBeforeWithdrawLP = MAINNET_DXN.balanceOf(address(bob));

        uint256 bobLPBalance = nxdDXNPair.balanceOf(address(bob));

        nxdDXNPair.approve(address(UNISWAP_V2_ROUTER), bobLPBalance);

        vm.expectRevert("UniswapV2: TRANSFER_FAILED");
        UNISWAP_V2_ROUTER.removeLiquidity(
            address(nxd), address(MAINNET_DXN), bobLPBalance, 0, 0, address(this), block.timestamp
        );

        assertEq(dxn.balanceOf(address(bob)), bobDXNBalanceBeforeWithdrawLP, "Bob DXN balance should not change");

        assertEq(nxd.balanceOf(address(bob)), bobNXDBalanceBeforeWithdrawLP, "Bob NXD balance should not change");

        assertEq(nxdDXNPair.balanceOf(address(bob)), bobLPBalance, "Bob LP balance should not change");
    }

    function testRevertWhenUnauthorizedRemovePairTokens() public {
        vm.expectRevert(NXDERC20.Unauthorized.selector);
        nxd.removePairTokens(address(0));
    }

    function testRevertWhenRemovePairTokensOfMainLP() public {
        address pair = address(nxd.uniswapV2Pair());
        vm.startPrank(bob);
        vm.expectRevert(NXDERC20.NoRemovalMainLP.selector);
        nxd.removePairTokens(pair);
    }

    function testRemovePairTokens() public {
        uint256 amountNXDToDeposit = 0.5 ether;

        vm.startPrank(alice);
        IERC20 unauthorizedToken = new MockToken(1 ether, "ROGUE", "ROGUE", 18);
        unauthorizedToken.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);

        dxn.approve(address(nxdProtocol), amountNXDToDeposit);
        nxdProtocol.deposit(amountNXDToDeposit, 1, true);
        // We now have NXD
        nxd.approve(address(UNISWAP_V2_ROUTER), type(uint256).max);
        UNISWAP_V2_ROUTER.addLiquidity(
            address(unauthorizedToken), address(nxd), 1 ether, amountNXDToDeposit, 0, 0, address(this), block.timestamp
        );
        address roguePair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(address(unauthorizedToken), address(nxd));
        vm.stopPrank();

        (uint256 depositedAfterTax,) = nxd.getAmountsAfterTax(alice, roguePair, amountNXDToDeposit);

        uint256 pairBalanceOfNXDBefore = nxd.balanceOf(address(roguePair));
        uint256 nxdBalanceOfBurnAddressBefore = nxd.balanceOf(address(DEADBEEF));

        (uint256 amountAfterTax, uint256 taxAmount) =
            nxd.getAmountsAfterTax(roguePair, address(DEADBEEF), depositedAfterTax);

        assertEq(pairBalanceOfNXDBefore, depositedAfterTax, "NXD balance =  taxed amountNXDToDeposit");

        vm.prank(bob);
        nxd.removePairTokens(address(roguePair));

        uint256 sellNXDAmount = (taxAmount * 7000) / 10000; // 85% (80% to buy and stake DXN, 5% to buy DXN and add liquidity to NXD/DXN pair)
        uint256 remainingTax = taxAmount - sellNXDAmount; // 15%
        uint256 burnAmount = (remainingTax * 666666666666666600) / 1e18; // 1% of all tax. 10% of tax amount. 66.66666666666666% of remaining tax

        assertEq(
            nxd.balanceOf(address(DEADBEEF)),
            nxdBalanceOfBurnAddressBefore + amountAfterTax + burnAmount,
            "NXD balance of burn addrses should increase"
        );
        assertEq(nxd.balanceOf(address(roguePair)), 0, "NXD balance of pair should be 0");
    }
}
