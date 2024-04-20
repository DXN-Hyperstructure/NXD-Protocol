import "forge-std/console.sol";
import "./NXD.Shared.t.sol";
import "../src/Vesting.sol";

contract VestingTest is NXDShared {
    function testSetUpVesting() public {
        assertEq(nxd.balanceOf(address(nxdVesting)), 0, "Vesting should have 0 NXD");
    }

    function depositAndFastForwardToLMPEnd() public {
        burnXen(charlie, true);
        vm.warp(startTime);
        uint256 nxdSupplyBeforeDeposits = nxd.totalSupply();
        uint256 amount = 1000000000000000000;
        uint256 dxnStartingBalanceOfBob = dxn.balanceOf(bob);
        uint256 dxnStartingBalanceOfAlice = dxn.balanceOf(alice);
        vm.startPrank(bob);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);

        uint256 secondsPassed = 1 days;
        vm.warp(startTime + secondsPassed);

        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);

        vm.stopPrank();

        secondsPassed = 14 days; // 14 days
        amount = 1 ether;
        vm.warp(startTime + secondsPassed);
        vm.startPrank(alice);
        dxn.approve(address(nxdProtocol), amount);
        nxdProtocol.deposit(amount, 0, false);
        vm.stopPrank();

        burnXen(charlie, false);

        vm.warp(block.timestamp + 1 days);
    }

    function testMintDevAlloc() public {
        depositAndFastForwardToLMPEnd();
        address[] memory recipients = new address[](3);
        recipients[0] = devRewardsRecepient1;
        recipients[1] = devRewardsRecepient2;
        recipients[2] = devRewardsRecepient3;
        vm.startPrank(bob);
        uint256 totalMinted = nxd.totalSupply();

        nxdProtocol.mintDevAlloc(recipients);

        uint256 expectedDevAlloc = ((totalMinted * 10000) / 9800) - totalMinted;
        uint256 balanceOfVesting = nxd.balanceOf(address(nxdVesting));

        assertEq(balanceOfVesting, expectedDevAlloc, "Vesting should have 2% of total minted");
    }

    function testClaimZero() public {
        depositAndFastForwardToLMPEnd();
        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 0");

        nxdVesting.claim();
        assertEq(nxd.balanceOf(devRewardsRecepient1), 0, "balance should be 0");

        uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmountAfter, 0, "claimable amount should be 0");
    }

    function testClaimHalf() public {
        depositAndFastForwardToLMPEnd();
        address[] memory recipients = new address[](3);
        recipients[0] = devRewardsRecepient1;
        recipients[1] = devRewardsRecepient2;
        recipients[2] = devRewardsRecepient3;
        vm.startPrank(bob);
        uint256 totalMinted = nxd.totalSupply();

        nxdProtocol.mintDevAlloc(recipients);

        vm.startPrank(devRewardsRecepient1);
        (, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);
        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 1/3 of total");
        uint256 divideTotalBy = 2; // half time has passed
        uint256 elapsed = nxdVesting.VESTING_DURATION_SECS() / divideTotalBy;
        vm.warp(start1 + elapsed);
        claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        uint256 expectedClaimableAmount = (nxd.balanceOf(address(nxdVesting)) / 3) / divideTotalBy;
        assertEq(claimableAmount, expectedClaimableAmount, "claimable amount should be half of total");

        nxdVesting.claim();
        assertEq(nxd.balanceOf(devRewardsRecepient1), expectedClaimableAmount, "balance should be half total");

        uint256 claimableAmountAfter = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmountAfter, 0, "claimable amount should be 0");
    }

    function testClaimAll() public {
        depositAndFastForwardToLMPEnd();
        address[] memory recipients = new address[](3);
        recipients[0] = devRewardsRecepient1;
        recipients[1] = devRewardsRecepient2;
        recipients[2] = devRewardsRecepient3;
        vm.startPrank(bob);
        uint256 totalMinted = nxd.totalSupply();

        nxdProtocol.mintDevAlloc(recipients);

        vm.startPrank(devRewardsRecepient1);
        (, uint256 start1) = nxdVesting.tokenAmountToVest(devRewardsRecepient1);

        uint256 claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        assertEq(claimableAmount, 0, "claimable amount should be 1/3 of total");
        uint256 elapsed = nxdVesting.VESTING_DURATION_SECS();
        vm.warp(start1 + elapsed);

        claimableAmount = nxdVesting.claimable(devRewardsRecepient1);
        uint256 expectedClaimableAmount = nxd.balanceOf(address(nxdVesting)) / 3;
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
        depositAndFastForwardToLMPEnd();
        address[] memory recipients = new address[](3);
        recipients[0] = devRewardsRecepient1;
        recipients[1] = devRewardsRecepient2;
        recipients[2] = devRewardsRecepient3;
        vm.startPrank(bob);
        uint256 totalMinted = nxd.totalSupply();

        nxdProtocol.mintDevAlloc(recipients);

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
