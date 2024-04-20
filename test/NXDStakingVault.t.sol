pragma solidity >=0.8.0;

import "forge-std/console.sol";
import "../src/NXDStakingVault.sol";
import "./NXD.Shared.t.sol";

contract NXDStakingVaultTest is NXDShared {
    uint256 public INITIAL_ETH_BALANCE = 1 ether;

    function setUp() public {
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), 10 ether);
        nxdProtocol.deposit(10 ether, 1, false);
        vm.stopPrank();

        vm.startPrank(alice);
        dxn.approve(address(nxdProtocol), 10 ether);
        nxdProtocol.deposit(10 ether, 1, false);
        vm.stopPrank();

        (IERC20 token, uint256 allocPoint, uint256 accEthPerShare, bool withdrawable) = nxdStakingVault.poolInfo(0);
        assertEq(address(token), address(nxd), "token should match");
        assertEq(allocPoint, 100, "allocPoint should match");
        assertEq(accEthPerShare, 0, "accEthPerShare should match");
        assertEq(withdrawable, true, "withdrawable should match");

        (, uint256 nxdAllocPoint,,) = nxdStakingVault.poolInfo(0);

        assertEq(
            nxdStakingVault.totalAllocPoint(),
            nxdAllocPoint,
            "totalAllocPoint should be this pool + NXD pool created earlier "
        );

        assertEq(nxdStakingVault.numPools(), 1, "poolLength should be 1");

        // Simulate the ETH rewards we have received from NXDProtocol
        vm.deal(address(nxdStakingVault), INITIAL_ETH_BALANCE);
    }

    function testSingleDeposit() public {
        spoofBalance(address(nxd), bob, 1000 ether);
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);
        (uint256 bobUserInfoAmount, uint256 userInfoRewardDebt) = nxdStakingVault.userInfo(0, bob);
        assertEq(bobUserInfoAmount, amountToStake, "staked amount should match");

        // Should be 0 because accEthPerShare is 0 because no rewards have been distributed
        uint256 expectedRewardDebt = 0;
        assertEq(userInfoRewardDebt, expectedRewardDebt, "Bob rewardDebt should be 0");
        vm.stopPrank();

        spoofBalance(address(nxd), alice, 1000 ether);

        vm.startPrank(alice);
        uint256 amountToStakeAlice = bobUserInfoAmount;
        nxd.approve(address(nxdStakingVault), amountToStakeAlice);
        nxdStakingVault.deposit(0, amountToStakeAlice);
        (, uint256 aliceRewardDebt) = nxdStakingVault.userInfo(0, alice);

        assertEq(aliceRewardDebt, expectedRewardDebt, "Alice rewardDebt should be 0");
    }

    // Tracks fuzzing of depositing multiple users
    mapping(address => uint256) public userStake;
    /// forge-config: default.fuzz.runs = 20

    function testFuzz_DepositMultipleUsers(uint256[] memory amountsToStake) public {
        vm.assume(amountsToStake.length < 10); // otherwise takes too long

        uint256 sum = 0;
        for (uint256 i = 0; i < amountsToStake.length; i++) {
            vm.assume(amountsToStake[i] < type(uint256).max / 1e18);
            vm.assume(amountsToStake[i] != 0);
            vm.assume(amountsToStake[i] + sum <= nxd.maxSupply());
            vm.assume(amountsToStake[i] + sum < type(uint256).max / 1e18);

            address user = vm.addr(amountsToStake[i] == 0 ? 1 : amountsToStake[i]);
            vm.startPrank(user);
            spoofBalance(address(dxn), user, amountsToStake[i]);
            // We now have DXN
            dxn.approve(address(nxdProtocol), amountsToStake[i]);
            nxdProtocol.deposit(amountsToStake[i], 1, true);

            // We now have `amountsToStake[i]` NXD

            nxd.approve(address(nxdStakingVault), amountsToStake[i]);
            (uint256 userInfoAmountBefore,) = nxdStakingVault.userInfo(0, user);
            console.log("Depositing % NXD", amountsToStake[i]);
            bool expectingRevert = false;
            // exepct revert if amount too large
            unchecked {
                if (amountsToStake[i] > address(nxdStakingVault).balance + amountsToStake[i]) {
                    expectingRevert = true;
                    vm.expectRevert();
                }
                if (amountsToStake[i] > userInfoAmountBefore + amountsToStake[i]) {
                    expectingRevert = true;
                    vm.expectRevert();
                }
            }

            nxdStakingVault.deposit(0, amountsToStake[i]);
            if (expectingRevert) {
                continue;
            }
            userStake[user] += amountsToStake[i];
            sum += amountsToStake[i];
            (,, uint256 accEthPerShare,) = nxdStakingVault.poolInfo(0);

            (uint256 userInfoAmount, uint256 userInfoRewardDebt) = nxdStakingVault.userInfo(0, user);
            assertEq(userInfoAmount, userStake[user], "staked amount should match");

            uint256 expectedRewardDebt = (userStake[user] * accEthPerShare) / 1e12;
            assertEq(userInfoRewardDebt, expectedRewardDebt, "rewardDebt should match expected");

            vm.stopPrank();

            // Simulate rewards being sent to the vault to trigger withdrawal of pending rewards
            vm.deal(address(this), amountsToStake[i] / 3);
            address(nxdStakingVault).call{value: amountsToStake[i] / 3}("");
            // nxdStakingVault.addPendingRewards();
        }

        uint256 nxdStakingVaultBal = nxd.balanceOf(address(nxdStakingVault));
        assertEq(nxdStakingVaultBal, sum, "nxdStakingVault balance should be sum of all staked amounts");
    }

    /// forge-config: default.fuzz.runs = 256
    // function testFuzz_DepositMultipleTimes(uint256[] memory amountsToStake) public {
    //     uint256 sum = 0;
    //     vm.startPrank(bob);
    //     for (uint256 i = 0; i < amountsToStake.length; i++) {
    //         vm.assume(amountsToStake[i] < type(uint256).max / 1e18);
    //         vm.assume(amountsToStake[i] != 0);
    //         vm.assume(amountsToStake[i] + sum <= nxd.maxSupply());
    //         vm.assume(amountsToStake[i] + sum < type(uint256).max / 1e18);

    //         spoofBalance(address(dxn), bob, amountsToStake[i]);
    //         // We now have DXN
    //         dxn.approve(address(nxdProtocol), amountsToStake[i]);
    //         nxdProtocol.deposit(amountsToStake[i], 1, true);

    //         // We now have `amountsToStake[i]` NXD

    //         nxd.approve(address(nxdStakingVault), amountsToStake[i]);
    //         (uint256 userInfoAmountBefore,) = nxdStakingVault.userInfo(0, bob);
    //         console.log("Depositing % NXD", amountsToStake[i]);
    //         bool expectingRevert = false;
    //         // exepct revert if amount too large
    //         unchecked {
    //             if (amountsToStake[i] > address(nxdStakingVault).balance + amountsToStake[i]) {
    //                 expectingRevert = true;
    //                 vm.expectRevert();
    //             }
    //             if (amountsToStake[i] > userInfoAmountBefore + amountsToStake[i]) {
    //                 expectingRevert = true;
    //                 vm.expectRevert();
    //             }
    //         }

    //         nxdStakingVault.deposit(0, amountsToStake[i]);
    //         if (expectingRevert) {
    //             continue;
    //         }
    //         sum += amountsToStake[i];
    //         (,, uint256 accEthPerShare,) = nxdStakingVault.poolInfo(0);

    //         (uint256 userInfoAmount, uint256 userInfoRewardDebt) = nxdStakingVault.userInfo(0, bob);
    //         assertEq(userInfoAmount, sum, "staked amount should match");
    //     }
    // }

    function testEmergencyWithdraw() public {
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);
        uint256 nxdBalanceBefore = nxd.balanceOf(bob);
        nxdStakingVault.emergencyWithdraw(0);
        assertEq(nxd.balanceOf(bob), nxdBalanceBefore + amountToStake, "Bob should have all his NXD back");
    }

    function testPendingETH() public {
        uint256 bobHarvestable = nxdStakingVault.pendingETH(0, bob);
        assertEq(bobHarvestable, 0, "Bob harvestable should be 0");

        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        console.log("Bob staking %s NXD", amountToStake);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);

        // Need to update to get latest pending rewards
        nxdStakingVault.massUpdatePools();

        bobHarvestable = nxdStakingVault.pendingETH(0, bob);
        assertEq(
            bobHarvestable, 0, "harvestable should be 0 because no rewards have been distributed after bob staking"
        );

        // Simulate ETH rewards being sent to the vault
        vm.deal(address(nxdStakingVault), INITIAL_ETH_BALANCE + 1 ether);
        nxdStakingVault.addPendingRewards();
        // Need to update to get latest pending rewards
        nxdStakingVault.massUpdatePools();
        bobHarvestable = nxdStakingVault.pendingETH(0, bob);
        console.log("new harvestable after 1 more eth staked: ", bobHarvestable);
        assertEq(bobHarvestable, address(nxdStakingVault).balance, "harvestable should be all ether");

        // Alice now stakes NXD
        vm.startPrank(alice);
        // Alice stakes same as what Bob staked
        (uint256 bobUserInfoAmount,) = nxdStakingVault.userInfo(0, bob);
        uint256 amountToStakeAlice = bobUserInfoAmount;
        nxd.approve(address(nxdStakingVault), amountToStakeAlice);
        nxdStakingVault.deposit(0, amountToStakeAlice);

        // Bob harvestable should still be all ETH because no rewards have been distributed after alice staking
        bobHarvestable = nxdStakingVault.pendingETH(0, bob);
        console.log("new bob harvestable after alice stakes: ", bobHarvestable);
        assertEq(bobHarvestable, (address(nxdStakingVault).balance), "bob harvestable should be half of all eth");
        uint256 etherAliceIsEligibleFor = 1 ether;
        // Simulate ETH rewards being sent to the vault.
        vm.deal(address(nxdStakingVault), address(nxdStakingVault).balance + etherAliceIsEligibleFor);
        nxdStakingVault.addPendingRewards();
        // Need to update to get latest pending rewards
        nxdStakingVault.massUpdatePools();

        uint256 newBobHarvestable = nxdStakingVault.pendingETH(0, bob);
        console.log("new bob harvestable after 1 more eth distributed: ", bobHarvestable);

        assertEq(
            newBobHarvestable,
            bobHarvestable + (etherAliceIsEligibleFor / 2),
            "bob harvestable should increase by half of new eth"
        );

        uint256 aliceHarvestable = nxdStakingVault.pendingETH(0, alice);
        // Alice should be eligible for half of the 1 ether distributed. Half because she and bob are staking exact same amounts
        assertEq(
            aliceHarvestable,
            etherAliceIsEligibleFor / 2,
            "alice harvestable should be half of 1 ether she is eligible for"
        );

        console.log("aliceHarvestable = ", aliceHarvestable);
    }

    function testWithdrawWithCooldown() public {
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);

        nxdStakingVault.deposit(0, amountToStake);
        nxdStakingVault.withdraw(0, amountToStake, false);

        vm.expectRevert(NXDStakingVault.Underflow.selector);
        nxdStakingVault.withdraw(0, amountToStake, false);

        uint256 expectedWithdrawAfterDate = block.timestamp + nxdStakingVault.WITHDRAWAL_COOLDOWN();
        (, uint256 bobUserInfoRewardDebt) = nxdStakingVault.userInfo(0, bob);

        console.log("bob rewardDebt");
        console.log(bobUserInfoRewardDebt);
        assertEq(nxd.balanceOf(bob), 0, "Bob should have 0 NXD");
        (uint256 amountRequest, uint256 canWithdrawAfterTimestamp) = nxdStakingVault.withdrawalRequests(0, bob);
        assertEq(canWithdrawAfterTimestamp, expectedWithdrawAfterDate, "Bob should be able to withdraw after 1 day");

        vm.warp(block.timestamp + nxdStakingVault.WITHDRAWAL_COOLDOWN() + 1);
        nxdStakingVault.withdrawCooldown(0);
        assertEq(nxd.balanceOf(bob), amountToStake, "Bob should have half of his NXD back");
    }

    function testWithdrawWithPenalty() public {
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);
        uint256 amountToWithdraw = amountToStake / 2;
        uint burnBalanceBefore = nxd.balanceOf(DEADBEEF);
        nxdStakingVault.withdraw(0, amountToWithdraw, true);

        uint256 expectedAmountAfterPenalty = (amountToWithdraw * 7500) / 10000;
        (uint256 amountRequest, uint256 canWithdrawAfterTimestamp) = nxdStakingVault.withdrawalRequests(0, bob);

        assertEq(amountRequest, 0, "Should remain 0");
        assertEq(canWithdrawAfterTimestamp, 0, "Should remain 0");

        assertEq(nxd.balanceOf(bob), expectedAmountAfterPenalty, "Bob should have half of his NXD back");
        assertEq(
            nxd.balanceOf(DEADBEEF) - burnBalanceBefore,
            amountToWithdraw - expectedAmountAfterPenalty,
            "25% penalty should be burnt"
        );
    }

    function testRevertWithdrawWhenCooldownNotOver() public {
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);

        uint256 amountToWithdraw = amountToStake / 2;
        nxdStakingVault.withdraw(0, amountToWithdraw, false);
        vm.expectRevert(NXDStakingVault.Cooldown.selector);
        nxdStakingVault.withdrawCooldown(0);
    }

    function testRevertWithdrawCooldownWhenNoRequestMade() public {
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);

        uint256 amountToWithdraw = amountToStake / 2;
        vm.expectRevert(NXDStakingVault.NoRequest.selector);
        nxdStakingVault.withdrawCooldown(0);
    }

    function testHarvest() public {
        uint256 amountToStake = nxd.balanceOf(bob);
        vm.startPrank(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);

        // Simulate rewards being sent to the vault
        vm.deal(address(nxdStakingVault), INITIAL_ETH_BALANCE + 1 ether);
        nxdStakingVault.addPendingRewards();
        nxdStakingVault.massUpdatePools();

        uint256 bobEthBalanceBefore = address(bob).balance;
        nxdStakingVault.withdraw(0, 0, false);
        uint256 expectedEthHarvested = INITIAL_ETH_BALANCE + 1 ether;
        assertEq(
            address(bob).balance,
            bobEthBalanceBefore + expectedEthHarvested,
            "Bob should have harvested all ETH rewards"
        );
    }

    function testDepositFor() public {
        (uint256 aliceInfoAmountBefore, uint256 aliceRewardDebtBefore) = nxdStakingVault.userInfo(0, alice);
        assertEq(aliceInfoAmountBefore, 0, "staked amount should be 0");

        // Bob deposits for alice
        vm.startPrank(bob);
        uint256 amountToStake = nxd.balanceOf(bob);
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.depositFor(alice, 0, amountToStake);

        uint256 balanceOfBobAfter = nxd.balanceOf(bob);

        (uint256 aliceInfoAmount, uint256 userInfoRewardDebt) = nxdStakingVault.userInfo(0, alice);
        assertEq(aliceInfoAmount, aliceInfoAmountBefore + amountToStake, "staked amount should match");

        assertEq(balanceOfBobAfter, 0, "Bob should have 0 NXD after depositing for alice");
    }

    function testFuzz_Harvest(uint256 amountToStake, uint256 ethRewards) public {
        vm.assume(amountToStake > 0 && amountToStake < type(uint256).max / 1e18);

        vm.assume(ethRewards < type(uint256).max / 1e18);

        vm.assume(amountToStake <= nxd.MAX_REWARDS_SUPPLY());

        vm.assume(amountToStake <= nxd.balanceOf(bob) && amountToStake <= nxd.balanceOf(alice));

        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amountToStake);
        nxdProtocol.deposit(amountToStake, 1, false);

        // Now bob has `amountToStake` NXD
        nxd.approve(address(nxdStakingVault), amountToStake);
        nxdStakingVault.deposit(0, amountToStake);
        console.log("nxdStakingVault balance before deal: ", address(nxdStakingVault).balance);

        vm.deal(address(nxdStakingVault), ethRewards);
        nxdStakingVault.addPendingRewards();
        nxdStakingVault.massUpdatePools();

        uint256 bobEthBalanceBefore = address(bob).balance;
        uint256 bobHarvestable = nxdStakingVault.pendingETH(0, bob);

        console.log("nxdStakingVault balance after deal: ", address(nxdStakingVault).balance);
        console.log("bobEthBalanceBefore: ", bobEthBalanceBefore);

        uint256 expectedAccEthPerShare = (ethRewards * 1e12) / amountToStake;
        assertEq(
            bobHarvestable, (amountToStake * expectedAccEthPerShare) / 1e12, "Bob pending ETH should be all ETH rewards"
        );

        // setting withdraw amount to 0 means harvest only
        nxdStakingVault.withdraw(0, 0, false);
        console.log("address(bob).balance after withdraw: ", address(bob).balance);

        assertEq(
            address(bob).balance,
            bobEthBalanceBefore + bobHarvestable,
            "Bob should have harvested all ETH rewards as sole staker"
        );
    }
}
