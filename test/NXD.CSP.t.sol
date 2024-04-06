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

contract CSP is NXDShared {
    // DBXenERC20 public dxn;
    // uint256 startTime = 1706135898003;
    // uint256 public endTime = startTime + 14 days;
    // uint256 initialRate = 1 ether; // starts 1:1 DXN:NXD (1 DXN = 1 NXD)
    // uint256 finalRate = 0.5 ether; //  ends 1:0.5 DXN:NXD (1 DXN = 0.5 NXD)
    // uint256 public constant decreasePerSecond = 413359788359788359788359788360;

    // uint256 internal bobPrivateKey;
    // uint256 internal alicePk;
    // uint256 internal charliePk;

    // address internal bob;
    // address internal alice;
    // address internal charlie;

    // XENCryptoMockMint public xen;
    // DBXen public dbxen;
    // DBXenViews public dbxenViews;

    // NXDProtocol public fundraiser;
    // NXDERC20 public nxd;
    // NXDStakingVault public nxdStakingVault;

    // uint256 public constant REFERRAL_CODE_1 = 1;
    // uint256 public constant REFERRAL_CODE_2 = 2;

    // uint256 public constant REFERRER_BONUS = 500; // 5% bonus for referring user
    // uint256 public constant REFERRAL_BONUS = 1000; // 10% bonus for referred user

    // uint256 public constant NXD_MAX_REWARDS_SUPPLY = 500000 ether;

    function setUp() public {
        // bobPrivateKey = 0xa11ce;
        // alicePk = 0xabc123;
        // charliePk = 0xdef456;

        // bob = vm.addr(bobPrivateKey);
        // alice = vm.addr(alicePk);
        // charlie = vm.addr(charliePk);

        // xen = new XENCryptoMockMint();
        // xen.transfer(bob, 300000000000 ether);
        // xen.transfer(alice, 300000000000 ether);
        // xen.transfer(charlie, 300000000000 ether);

        // dbxen = new DBXen(address(0), address(xen));
        // dbxenViews = new DBXenViews(dbxen);

        // dxn = dbxen.dxn();
        // dxn.mint(bob, 10000000 ether);
        // dxn.mint(alice, 10000000 ether);

        // vm.label(address(dxn), "DXN");

        // fundraiser = new NXDProtocol(
        //     10000 ether,
        //     address(dxn),
        //     address(dbxen),
        //     address(dbxenViews)
        // );
        // nxd = nxdProtocol.nxd();
        // nxdStakingVault = nxdProtocol.nxdStakingVault();

        vm.prank(charlie);
        nxdProtocol.setReferralCode(REFERRAL_CODE_1);
    }

    function testSetup() public {
        assertEq(nxd.name(), "NXD Token");
        assertEq(nxd.symbol(), "NXD");
        assertEq(nxd.decimals(), 18);
        assertEq(nxdProtocol.currentRate(), initialRate);
    }

    function testCurrentRate() public {
        // console.log("nxd start time: %s", nxd.startTime());
        // console.log("Current rate: %s", nxdProtocol.currentRate());
        assertEq(nxdProtocol.currentRate(), initialRate);
        console.log("decreasePersecond: %s", nxdProtocol.decreasePerSecond());

        uint256 secondsPassed = 7 days;
        vm.warp(startTime + secondsPassed);
        uint256 expectedRate = 0.75 ether;
        assertEq(nxdProtocol.currentRate(), expectedRate);

        secondsPassed = 14 days;
        vm.warp(startTime + secondsPassed);
        expectedRate = finalRate;
        assertEq(nxdProtocol.currentRate(), expectedRate);
    }

    function burnXen(address from, bool claim) public {
        vm.txGasPrice(19000000);
        vm.startPrank(from);
        vm.deal(from, 1 ether);

        uint256 batchNumber = 1;
        xen.approve(address(dbxen), batchNumber * dbxen.XEN_BATCH_AMOUNT());
        dbxen.burnBatch{value: 1 ether}(batchNumber);
        uint256 cycleAccruedFees = dbxen.cycleAccruedFees(dbxen.currentCycle());
        console.log("DBXen cycleAccruedFees: %s", cycleAccruedFees);

        if (claim) {
            vm.warp(block.timestamp + 1 days);
            uint256 expectedUnclaimedFees = dbxenViews.getUnclaimedFees(from);
            console.log("Unclaimed fees: %s", expectedUnclaimedFees);
            console.log("DBXen ETH balace = ", address(dbxen).balance);
            dbxen.claimFees();
            expectedUnclaimedFees = dbxenViews.getUnclaimedFees(from);
            console.log("Unclaimed fees after claim: %s", expectedUnclaimedFees);
        }
        vm.stopPrank();
    }

    function testRevertWhenDepositBeforeLPCreation() public {
        vm.startPrank(bob);
        NXDProtocol _nxdProtocol = new NXDProtocol(
            10000 ether, address(dbxen), address(dbxenViews), address(v3Oracle), bob, address(nxdVesting), devFeeTo
        );
        nxd = _nxdProtocol.nxd();
        vm.expectRevert(NXDProtocol.NotInitialized.selector);
        _nxdProtocol.deposit(1, 0, false);
    }

    function testRevertWhenDepositZero() public {
        vm.startPrank(bob);
        vm.expectRevert(NXDProtocol.InvalidAmount.selector);
        nxdProtocol.deposit(0, 0, false);
    }

    function testReferralBonuses() public {
        uint256 amount = 1000 ether;
        (uint256 referrerAmount, uint256 userAmount) = nxdProtocol.getReferralBonuses(amount);
        assertEq(referrerAmount, 50 ether, "Referrer amount");
        assertEq(userAmount, 100 ether, "User amount");
    }

    function testDepositWithoutReferrer() public {
        burnXen(charlie, true);
        vm.warp(startTime);
        uint256 nxdSupplyBeforeDeposits = nxd.totalSupply();
        uint256 amount = 1000000000000000000;
        uint256 dxnStartingBalanceOfBob = dxn.balanceOf(bob);
        uint256 dxnStartingBalanceOfAlice = dxn.balanceOf(alice);
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);

        uint256 expectedBobNxdAfterFirstDeposit = (amount * initialRate) / 1e18;

        assertEq(nxd.balanceOf(bob), expectedBobNxdAfterFirstDeposit);
        assertEq(dxn.balanceOf(bob), dxnStartingBalanceOfBob - amount);
        assertEq(nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedBobNxdAfterFirstDeposit);

        uint256 secondsPassed = 1 days;
        vm.warp(startTime + secondsPassed);
        uint256 expectedRate = ((initialRate) - ((secondsPassed * decreasePerSecond) / 1e18));

        uint256 expectedNxd = (amount * expectedRate) / 1e18;

        nxdSupplyBeforeDeposits = nxd.totalSupply();

        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);
        assertEq(
            nxd.balanceOf(bob), expectedNxd + expectedBobNxdAfterFirstDeposit, "Bob's NXD balance after second deposit"
        );
        assertEq(dxn.balanceOf(bob), dxnStartingBalanceOfBob - (2 * amount), "dxn.balanceOf(bob)");

        assertEq(nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedNxd, "NXD total supply after BOB second deposit");

        vm.stopPrank();

        secondsPassed = 14 days; // 14 days
        amount = 1 ether;
        vm.warp(startTime + secondsPassed);
        expectedRate = finalRate;

        expectedNxd = (amount * expectedRate) / 1e18;
        nxdSupplyBeforeDeposits = nxd.totalSupply();
        vm.startPrank(alice);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);
        vm.stopPrank();
        assertEq(nxd.balanceOf(alice), expectedNxd);
        assertEq(dxn.balanceOf(alice), dxnStartingBalanceOfAlice - amount);
        assertEq(
            nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedNxd, "NXD total supply after Alice second deposit"
        );

        burnXen(charlie, false);

        uint256 expectedUnclaimedFees = nxdProtocol.ourClaimableFees();
        console.log("Fundraiser unclaimed fees before we reach next cycle: %s", expectedUnclaimedFees);

        vm.warp(block.timestamp + 1 days);
        uint256 charlieExpectedUnclaimedFees = dbxenViews.getUnclaimedFees(charlie);
        console.log("Charlie's unclaimed fees: %s", charlieExpectedUnclaimedFees);

        uint256 accruedFees = dbxen.cycleAccruedFees(dbxen.currentCycle());
        // uint fundraiserShareOfFees = (accruedFees * 10) / 100;
        console.log("cycleAccruedFees = ", accruedFees);
        expectedUnclaimedFees = nxdProtocol.ourClaimableFees();
        console.log("Fundraiser Unclaimed fees: %s", expectedUnclaimedFees);
    }

    function testDepositWithoutReferrerWithCollectFees_Fork() public {
        burnXen(charlie, true);
        vm.warp(startTime);
        uint256 nxdSupplyBeforeDeposits = nxd.totalSupply();
        uint256 amount = 1000000000000000000;
        uint256 dxnStartingBalanceOfBob = MAINNET_DXN.balanceOf(bob);
        uint256 dxnStartingBalanceOfAlice = MAINNET_DXN.balanceOf(alice);
        vm.startPrank(bob);
        MAINNET_DXN.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);

        uint256 expectedBobNxdAfterFirstDeposit = (amount * initialRate) / 1e18;

        assertEq(nxd.balanceOf(bob), expectedBobNxdAfterFirstDeposit);
        assertEq(MAINNET_DXN.balanceOf(bob), dxnStartingBalanceOfBob - amount);
        assertEq(nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedBobNxdAfterFirstDeposit);

        uint256 secondsPassed = 1 days;
        vm.warp(startTime + secondsPassed);
        uint256 expectedRate = ((initialRate) - ((secondsPassed * decreasePerSecond) / 1e18));

        uint256 expectedNxd = (amount * expectedRate) / 1e18;

        nxdSupplyBeforeDeposits = nxd.totalSupply();

        MAINNET_DXN.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);
        assertEq(
            nxd.balanceOf(bob), expectedNxd + expectedBobNxdAfterFirstDeposit, "Bob's NXD balance after second deposit"
        );
        assertEq(MAINNET_DXN.balanceOf(bob), dxnStartingBalanceOfBob - (2 * amount), "MAINNET_DXN.balanceOf(bob)");

        assertEq(nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedNxd, "NXD total supply after BOB second deposit");

        vm.stopPrank();

        secondsPassed = 14 days; // 14 days
        amount = 1 ether;
        vm.warp(startTime + secondsPassed);
        expectedRate = finalRate;

        expectedNxd = (amount * expectedRate) / 1e18;
        nxdSupplyBeforeDeposits = nxd.totalSupply();
        vm.startPrank(alice);
        MAINNET_DXN.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);
        vm.stopPrank();
        assertEq(nxd.balanceOf(alice), expectedNxd);
        assertEq(MAINNET_DXN.balanceOf(alice), dxnStartingBalanceOfAlice - amount);
        assertEq(
            nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedNxd, "NXD total supply after Alice second deposit"
        );

        burnXen(charlie, false);

        uint256 expectedUnclaimedFees = nxdProtocol.ourClaimableFees();
        console.log("Fundraiser unclaimed fees before we reach next cycle: %s", expectedUnclaimedFees);

        vm.warp(block.timestamp + 1 days);
        uint256 charlieExpectedUnclaimedFees = dbxenViews.getUnclaimedFees(charlie);
        console.log("Charlie's unclaimed fees: %s", charlieExpectedUnclaimedFees);

        uint256 accruedFees = dbxen.cycleAccruedFees(dbxen.currentCycle());
        // uint fundraiserShareOfFees = (accruedFees * 10) / 100;
        console.log("cycleAccruedFees = ", accruedFees);
        expectedUnclaimedFees = nxdProtocol.ourClaimableFees();
        console.log("Fundraiser Unclaimed fees: %s", expectedUnclaimedFees);

        // Next deposit should trigger claimFee
        uint256 burnedDXNBefore = dxn.balanceOf(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF);
        uint256 burnedNXDBefore = nxd.balanceOf(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF);
        vm.startPrank(alice);
        MAINNET_DXN.approve(address(nxdProtocol), amount);
        // vm.expectEmit(true, true, true, true);
        nxdProtocol.depositNoMint(amount);
        vm.stopPrank();

        // We should have executed our strategy now.

        uint256 ethToSwapForDXN = (expectedUnclaimedFees * 8500) / 10000;
        uint256 remaining = expectedUnclaimedFees - ethToSwapForDXN;

        assertEq(address(nxdStakingVault).balance, remaining, "Remaining ETH should be sent to Staking Vault");

        assertLt(
            burnedDXNBefore, dxn.balanceOf(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), "Burned DXN should increase"
        );
        assertLt(
            burnedNXDBefore, nxd.balanceOf(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), "Burned NXD should increase"
        );

        assertEq(nxdProtocol.pendingDXNToStake(), 0, "Pending DXN to stake should be 0");
    }

    function testDepositWithReferrer() public {
        uint256 nxdSupplyBeforeDeposits = nxd.totalSupply();
        uint256 amount = 10000 ether; // 10k DXN
        uint256 dxnStartingBalanceOfBob = dxn.balanceOf(bob);
        uint256 dxnStartingBalanceOfAlice = dxn.balanceOf(alice);

        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, REFERRAL_CODE_1, false);

        uint256 expectedBobNxdAfterFirstDeposit = (amount * initialRate) / 1e18;
        uint256 expectedReferrerNXD = (expectedBobNxdAfterFirstDeposit * REFERRER_BONUS) / 10000; // 5% bonus for referring user
        // Add 10% bonus for referred user
        uint256 expectedBobBonus = (expectedBobNxdAfterFirstDeposit * REFERRAL_BONUS) / 10000;
        assertEq(nxd.balanceOf(bob), expectedBobNxdAfterFirstDeposit, "Bob's NXD balance after first deposit");
        assertEq(dxn.balanceOf(bob), dxnStartingBalanceOfBob - amount, "Bob's DXN balance after first deposit");
        assertEq(
            nxd.totalSupply(),
            nxdSupplyBeforeDeposits + expectedBobNxdAfterFirstDeposit,
            "NXD total supply after first deposit"
        );
        assertEq(nxdProtocol.referrerRewards(charlie), expectedReferrerNXD, "Charlie's referrer rewards");
        assertEq(nxdProtocol.referredRewards(bob), expectedBobBonus, "Bob's referred rewards");

        // Another deposit after 7 days
        uint256 secondsPassed = 7 days;
        vm.warp(startTime + secondsPassed);
        uint256 expectedRate = 0.75 ether;

        uint256 expectedNxd = (amount * expectedRate) / 1e18;
        expectedReferrerNXD += (expectedNxd * REFERRER_BONUS) / 10000; // 5% bonus for referring user
        // Add 10% bonus for referred user
        expectedBobBonus += (expectedNxd * REFERRAL_BONUS) / 10000;

        nxdSupplyBeforeDeposits = nxd.totalSupply();

        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, REFERRAL_CODE_1, false);
        assertEq(
            nxd.balanceOf(bob), expectedNxd + expectedBobNxdAfterFirstDeposit, "Bob's NXD balance after second deposit"
        );
        assertEq(dxn.balanceOf(bob), dxnStartingBalanceOfBob - (amount * 2), "dxn.balanceOf(bob)");
        assertEq(nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedNxd, "NXD total supply after BOB second deposit");
        assertEq(nxdProtocol.referrerRewards(charlie), expectedReferrerNXD, "Charlie's referrer rewards");
        assertEq(nxdProtocol.referredRewards(bob), expectedBobBonus, "Bob's referred rewards");

        vm.stopPrank();

        nxdSupplyBeforeDeposits = nxd.totalSupply();

        secondsPassed = 14 days; // 14 days
        vm.warp(startTime + secondsPassed);
        expectedRate = finalRate;

        expectedNxd = (amount * expectedRate) / 1e18;
        uint256 expectedReferrerNXD3rdDeposit = (expectedNxd * REFERRER_BONUS) / 10000; // 5% bonus for referring user
        // Add 10% bonus for referred user
        uint256 aliceBonus = (expectedNxd * REFERRAL_BONUS) / 10000;
        vm.startPrank(alice);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, REFERRAL_CODE_1, false);
        vm.stopPrank();
        assertEq(nxd.balanceOf(alice), expectedNxd, "Alice's NXD balance after deposit");
        assertEq(dxn.balanceOf(alice), dxnStartingBalanceOfAlice - amount, "Alice's DXN balance after deposit");
        assertEq(
            nxd.totalSupply(), nxdSupplyBeforeDeposits + expectedNxd, "NXD total supply after Alice second deposit"
        );
        assertEq(
            nxdProtocol.referrerRewards(charlie),
            expectedReferrerNXD + expectedReferrerNXD3rdDeposit,
            "Charlie's referrer rewards"
        );
        assertEq(nxdProtocol.referredRewards(alice), aliceBonus, "Alice's referred rewards");
    }

    function testDepositNoMint() public {
        uint256 nxdSupplyBeforeDeposits = nxd.totalSupply();
        uint256 amount = 1000000000000000000;
        uint256 nxdStartingBalanceOfBob = nxd.balanceOf(bob);
        uint256 dxnStartingBalanceOfBob = dxn.balanceOf(bob);
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.depositNoMint(amount);

        assertEq(nxd.balanceOf(bob), nxdStartingBalanceOfBob, "Bob's NXD balance after deposit should be the same.");
        assertEq(dxn.balanceOf(bob), dxnStartingBalanceOfBob - amount, "Bob's DXN balance after deposit");
        assertEq(nxd.totalSupply(), nxdSupplyBeforeDeposits, "NXD total supply after deposit");

        // DBXen should have increased our stake

        uint256 protocolStaked = dbxen.accStakeCycle(address(nxdProtocol), dbxen.currentCycle() + 1);
        assertEq(protocolStaked, amount, "Protocol staked amount should match");

        assertEq(
            dbxen.accFirstStake(address(nxdProtocol)), dbxen.currentCycle() + 1, "Fundraiser first stake should match"
        );
    }

    function testRevertWhenMaxSupplyExceededNoReferral() public {
        uint256 amount = NXD_MAX_REWARDS_SUPPLY + 1;
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        vm.expectRevert(NXDProtocol.NXDMaxSupplyMinted.selector);
        nxdProtocol.deposit(amount, 0, false);
    }

    function testRevertWhenMaxSupplyExceededWithReferral() public {
        uint256 amount = NXD_MAX_REWARDS_SUPPLY + 1;
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        vm.expectRevert(NXDProtocol.NXDMaxSupplyMinted.selector);
        nxdProtocol.deposit(amount, 1, false);
    }

    function testDepositWhenMaxSupplyExceedWithDynamicAmount() public {
        uint256 amount = NXD_MAX_REWARDS_SUPPLY + 1;
        uint256 bobDxnBalance = dxn.balanceOf(bob);
        uint256 bobNxdBalance = nxd.balanceOf(bob);
        uint256 remainingSupply = nxd.maxSupply() - nxd.totalSupply();
        uint256 expectedBobNxd =
            remainingSupply - ((((remainingSupply * 1.15 ether - (remainingSupply * 1e18)) * 1e18) / 1.15 ether) / 1e18);
        uint256 referredBonusAmount = (expectedBobNxd * REFERRAL_BONUS) / 10000; // 10% bonus for referred user
        uint256 referrerBonusAmount = (expectedBobNxd * REFERRER_BONUS) / 10000; // 10% bonus for referred user

        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 1, true);
        uint256 dxnTakenFromBob = bobDxnBalance - dxn.balanceOf(bob);
        assertEq((dxnTakenFromBob * 1.15 ether) / 1e18, remainingSupply, "DXN taken from Bob");

        assertEq(nxd.balanceOf(bob), expectedBobNxd + bobNxdBalance, "Bob's NXD balance after deposit");
        assertEq(
            nxd.totalSupply() + referredBonusAmount + referrerBonusAmount,
            nxd.maxSupply(),
            "NXD total supply after deposit"
        );
        assertEq(nxdProtocol.referrerRewards(charlie), referrerBonusAmount, "Charlie's referrer rewards");
        assertEq(nxdProtocol.referredRewards(bob), referredBonusAmount, "Bob's referred rewards");
    }

    function testSetReferralCode() public {
        vm.startPrank(bob);
        nxdProtocol.setReferralCode(REFERRAL_CODE_2);
        vm.stopPrank();
        assertEq(nxdProtocol.referralCodes(REFERRAL_CODE_2), bob, "Bob's referral code");
    }

    function testRevertWhenSetReferralCodeToZero() public {
        vm.startPrank(bob);
        vm.expectRevert(NXDProtocol.InvalidReferralCode.selector);
        nxdProtocol.setReferralCode(0);
    }

    function testRevertWhenSetReferralCodeAlreadyUsed() public {
        vm.startPrank(bob);
        vm.expectRevert(NXDProtocol.ReferralCodeAlreadySet.selector);
        nxdProtocol.setReferralCode(REFERRAL_CODE_1);
    }

    function testRevertWhenAutoReferral() public {
        uint256 amount = 10000 ether; // 10k DXN
        vm.startPrank(charlie);
        dxn.approve(address(nxdProtocol), amount);
        vm.expectRevert(NXDProtocol.NoAutoReferral.selector);
        nxdProtocol.deposit(amount, REFERRAL_CODE_1, false);
    }

    function testWithdrawReferralRewards() public {
        uint256 amount = 10000 ether; // 10k DXN
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, REFERRAL_CODE_1, false);

        uint256 expectedBobNxdAfterFirstDeposit = (amount * initialRate) / 1e18;
        uint256 expectedReferrerNXD = (expectedBobNxdAfterFirstDeposit * REFERRER_BONUS) / 10000; // 5% bonus for referring user
        // Add 10% bonus for referred user
        uint256 expectedBobBonus = (expectedBobNxdAfterFirstDeposit * REFERRAL_BONUS) / 10000;

        assertEq(
            nxdProtocol.referrerRewards(charlie), expectedReferrerNXD, "Charlie's referrer rewards before withdraw"
        );
        assertEq(nxdProtocol.referredRewards(bob), expectedBobBonus, "Bob's referred rewards before withdraw");

        uint256 bobBalanceBeforeWithdraw = nxd.balanceOf(bob);
        uint256 charlieBalanceBeforeWithdraw = nxd.balanceOf(charlie);
        vm.warp(startTime + 14 days);

        nxdProtocol.withdrawReferralRewards();
        assertEq(nxdProtocol.referredRewards(bob), 0, "Bob's referred rewards after withdraw");
        assertEq(nxd.balanceOf(bob), bobBalanceBeforeWithdraw + expectedBobBonus, "Bob's NXD balance after withdraw");
        vm.stopPrank();
        vm.prank(charlie);
        nxdProtocol.withdrawReferralRewards();
        assertEq(nxdProtocol.referrerRewards(charlie), 0, "Charlie's referrer rewards after withdraw");
        assertEq(
            nxd.balanceOf(charlie),
            charlieBalanceBeforeWithdraw + expectedReferrerNXD,
            "Charlie's NXD balance after withdraw"
        );
    }

    function testRevertWhenWithdrawReferralRewardsZero() public {
        vm.startPrank(bob);
        vm.warp(startTime + 14 days);
        vm.expectRevert(NXDProtocol.NoRewards.selector);
        nxdProtocol.withdrawReferralRewards();
    }

    function testRevertWhenWithdrawReferralRewardsBeforeFundraiseEnd() public {
        uint256 amount = 10000 ether; // 10k DXN
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, REFERRAL_CODE_1, false);

        uint256 expectedBobNxdAfterFirstDeposit = (amount * initialRate) / 1e18;
        uint256 expectedReferrerNXD = (expectedBobNxdAfterFirstDeposit * REFERRER_BONUS) / 10000; // 5% bonus for referring user
        // Add 10% bonus for referred user
        uint256 expectedBobBonus = (expectedBobNxdAfterFirstDeposit * REFERRAL_BONUS) / 10000;

        assertEq(
            nxdProtocol.referrerRewards(charlie), expectedReferrerNXD, "Charlie's referrer rewards before withdraw"
        );
        assertEq(nxdProtocol.referredRewards(bob), expectedBobBonus, "Bob's referred rewards before withdraw");

        vm.warp(startTime + 13 days); // before fundraiser ends

        vm.expectRevert(NXDProtocol.CSPOngoing.selector);
        nxdProtocol.withdrawReferralRewards();
        assertEq(nxdProtocol.referredRewards(bob), expectedBobBonus, "Bob's referred rewards after withdraw attempt");
        vm.stopPrank();

        vm.startPrank(charlie);
        vm.expectRevert(NXDProtocol.CSPOngoing.selector);
        nxdProtocol.withdrawReferralRewards();
        assertEq(
            nxdProtocol.referrerRewards(charlie),
            expectedReferrerNXD,
            "Charlie's referrer rewards after withdraw attempt"
        );
    }

    function testRevertDepositWhenCSPHasEnded() public {
        uint256 amount = 1000000000000000000;
        vm.warp(endTime + 1);
        dxn.approve(address(nxdProtocol), amount);
        vm.expectRevert(NXDProtocol.CSPHasEnded.selector);
        nxdProtocol.deposit(amount, 0, false);
    }
}
