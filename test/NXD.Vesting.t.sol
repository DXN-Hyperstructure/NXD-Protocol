import "forge-std/console.sol";
import "./NXD.Shared.t.sol";
import "../src/Vesting.sol";

contract VestingTest is NXDShared {
    function testSetUpVesting() public {
        assertEq(nxd.balanceOf(address(nxdVesting)), NXD_DEV_REWARDS_SUPPLY);
        (uint256 amount1, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);
        (uint256 amount2, uint256 start2) = nxdVesting.tokenAmountToVest(devRewardsRecepient2);
        (uint256 amount3, uint256 start3) = nxdVesting.tokenAmountToVest(devRewardsRecepient3);

        assertEq(amount1, NXD_DEV_REWARDS_SUPPLY / 3, "amount 1 should be 1/3 of total");
        assertEq(amount2, NXD_DEV_REWARDS_SUPPLY / 3, "amount 2 should be 1/3 of total");
        assertEq(amount3, NXD_DEV_REWARDS_SUPPLY / 3, "amount 3 should be 1/3 of total");

        assertEq(start1, block.timestamp, "start time should be now");
        assertEq(start2, block.timestamp, "start time should be now");
        assertEq(start3, block.timestamp, "start time should be now");

        assertEq(nxdVesting.claimable(devRewardsRecepient1), 0, "claimable amount should be 0");
    }

    function testClaimZero() public {
        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 0");

        nxdVesting.claim();
        assertEq(nxd.balanceOf(devRewardsRecepient1), 0, "balance should be 0");

        uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmountAfter, 0, "claimable amount should be 0");
    }

    function testClaimHalf() public {
        vm.startPrank(devRewardsRecepient1);
        (, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);
        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 1/3 of total");
        uint256 divideTotalBy = 2; // half time has passed
        uint256 elapsed = nxdVesting.VESTING_DURATION_SECS() / divideTotalBy;
        vm.warp(start1 + elapsed);
        claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        uint256 expectedClaimableAmount = (NXD_DEV_REWARDS_SUPPLY / 3) / divideTotalBy;
        assertEq(claimableAmount, expectedClaimableAmount, "claimable amount should be half of total");

        nxdVesting.claim();
        assertEq(nxd.balanceOf(devRewardsRecepient1), expectedClaimableAmount, "balance should be half total");

        uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmountAfter, 0, "claimable amount should be 0");
    }

    function testClaimAll() public {
        vm.startPrank(devRewardsRecepient1);
        (, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);

        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 1/3 of total");
        uint256 elapsed = nxdVesting.VESTING_DURATION_SECS();
        vm.warp(start1 + elapsed);

        claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        uint256 expectedClaimableAmount = NXD_DEV_REWARDS_SUPPLY / 3;
        assertEq(claimableAmount, expectedClaimableAmount, "claimable amount should be total");

        nxdVesting.claim();
        assertEq(nxd.balanceOf(devRewardsRecepient1), expectedClaimableAmount, "balance should be total");

        uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmountAfter, 0, "claimable amount should be 0");
    }

    function testFuzz_claimable(uint256 elapsed) public {
        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 0");

        (uint256 amount1, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);
        vm.assume(elapsed <= type(uint256).max - start1);

        vm.warp(start1 + elapsed);
        uint256 expectedClaimableAmount;

        if (elapsed >= nxdVesting.VESTING_DURATION_SECS()) {
            expectedClaimableAmount = amount1;
        } else {
            expectedClaimableAmount = (amount1 * elapsed) / nxdVesting.VESTING_DURATION_SECS();
        }

        uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmountAfter, expectedClaimableAmount, "claimable amount should match");
    }

    /// forge-config: default.fuzz.runs = 20
    function testFuzz_claimAll(uint256[] memory elapsed) public {
        vm.startPrank(devRewardsRecepient1);
        uint256 lastTime = 0;

        for (uint256 i = 0; i < elapsed.length; i++) {
            uint256 balanceOfBefore = nxd.balanceOf(devRewardsRecepient1);
            (uint256 amount1, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);

            vm.assume(elapsed[i] <= type(uint256).max / amount1);
            vm.assume(start1 + elapsed[i] >= lastTime);

            lastTime = start1 + elapsed[i];

            uint256 expectedClaimableAmount;
            uint256 claimed = nxdVesting.claimed(devRewardsRecepient1);
            console.log("elapsed[i] = ", elapsed[i]);

            if (elapsed[i] >= nxdVesting.VESTING_DURATION_SECS()) {
                expectedClaimableAmount = amount1 - claimed;
            } else {
                if (claimed == amount1 || elapsed[i] == 0) {
                    expectedClaimableAmount = 0;
                } else {
                    expectedClaimableAmount = (amount1 * elapsed[i]) / nxdVesting.VESTING_DURATION_SECS() - claimed;
                }
            }
            console.log("testFuzz_claimAll: expectedClaimableAmount = ", expectedClaimableAmount);

            vm.warp(start1 + elapsed[i]);

            uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
            assertEq(claimableAmount, expectedClaimableAmount, "claimable amount should match");

            nxdVesting.claim();
            assertEq(
                nxd.balanceOf(devRewardsRecepient1),
                balanceOfBefore + expectedClaimableAmount,
                "balance should increase"
            );

            uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
            assertEq(claimableAmountAfter, 0, "claimable amount should be 0");
        }
    }

    function testRevertWhenSetTokenAlreadySet() public {
        vm.startPrank(bob);
        vm.expectRevert(Vesting.AlreadySet.selector);
        nxdVesting.setToken(address(nxd));
        assertEq(address(nxdVesting.token()), address(nxd), "token should be set");
    }

    function testRevertWhenSetTokenZero() public {
        Vesting newVesting = new Vesting();
        vm.expectRevert(Vesting.NotValidToken.selector);
        newVesting.setToken(address(0));
        assertEq(address(newVesting.token()), address(0), "token should still be 0");
    }

    function testRevertWhenSetTokenNotOwner() public {
        vm.expectRevert(Vesting.Owner.selector);
        nxdVesting.setToken(address(1));
        assertEq(address(nxdVesting.token()), address(nxd), "token should remain same");
    }

    function testSetToken() public {
        vm.startPrank(bob);
        Vesting newVesting = new Vesting();
        newVesting.setToken(address(nxd));
        assertEq(address(newVesting.token()), address(nxd), "token should be set");
    }
}
