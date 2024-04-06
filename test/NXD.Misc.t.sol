pragma solidity >=0.8.0;

import "./NXD.Shared.t.sol";

contract NXDMisc is NXDShared {
    function testCreatePoolSetUp() public {
        (uint256 res0, uint256 res1,) = nxdDXNPair.getReserves();
        assertEq(res0, address(nxd) > address(nxd) ? NXD_INITIAL_LP_SUPPLY : 1000 ether, "reserve 0 should match");
        assertEq(res1, address(nxd) > address(nxd) ? 1000 ether : NXD_INITIAL_LP_SUPPLY, "reserve 1 should match");
        assertEq(nxdDXNPair.token0(), address(nxd) > address(nxd) ? address(nxd) : address(dxn), "token0 should match");
        assertEq(nxdDXNPair.token1(), address(nxd) > address(nxd) ? address(dxn) : address(nxd), "token1 should match");
        assertEq(address(nxdProtocol.v2Oracle()), address(nxd.v2Oracle()), "V2Oracle should match");
        assertEq(address(nxd.uniswapV2Pair()), address(nxdDXNPair), "LP should match");
    }

    function testCreatePool() public {
        uint256 nxdDesired = 10000 ether;
        uint256 dxnDesired = 1000 ether;
        address to = address(bob);

        vm.startPrank(bob);

        NXDProtocol _nxdProtocol = new NXDProtocol(
            10000 ether, address(dbxen), address(dbxenViews), address(v3Oracle), bob, address(nxdVesting), devFeeTo
        );
        nxd = _nxdProtocol.nxd();

        console.log("Bob DXN balance =", dxn.balanceOf(bob));
        nxd.approve(address(_nxdProtocol), nxdDesired);
        dxn.approve(address(_nxdProtocol), dxnDesired);
        _nxdProtocol.createPool(nxdDesired, dxnDesired, to, block.timestamp);

        nxdDXNPair = IUniswapV2PairLocal(
            IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(address(MAINNET_DXN), address(nxd))
        );

        (uint256 res0, uint256 res1,) = nxdDXNPair.getReserves();
        (uint256 resNXD, uint256 resDXN) = nxdDXNPair.token0() == address(nxd) ? (res0, res1) : (res1, res0);

        assertEq(nxd.balanceOf(address(nxdDXNPair)), nxdDesired, "NXD balane should match");
        assertEq(dxn.balanceOf(address(nxdDXNPair)), dxnDesired, "DXN balance should match");

        assertEq(resNXD, nxdDesired, "NXD reserve should match");
        assertEq(resDXN, dxnDesired, "DXN reserve should match");

        assertEq(nxdDXNPair.token0(), address(nxd) > address(dxn) ? address(dxn) : address(nxd), "token0 should match");
        assertEq(nxdDXNPair.token1(), address(nxd) > address(dxn) ? address(nxd) : address(dxn), "token1 should match");

        assertEq(address(_nxdProtocol.v2Oracle()), address(nxd.v2Oracle()), "V2Oracle should match");
        assertEq(address(nxd.uniswapV2Pair()), address(nxdDXNPair), "LP should match");
    }

    function testFuzz_CreatePool(uint256 nxdDesired, uint256 dxnDesired) public {
        vm.assume(nxdDesired >= 1000 && dxnDesired >= 1000);
        vm.assume(nxdDesired <= 10000 ether); // 10k. Our initial balance after deploying NXDProtocol
        vm.assume(dxnDesired <= dxn.balanceOf(bob));

        address to = address(bob);

        vm.startPrank(bob);
        NXDProtocol _nxdProtocol = new NXDProtocol(
            10000 ether, address(dbxen), address(dbxenViews), address(v3Oracle), bob, address(nxdVesting), devFeeTo
        );
        nxd = _nxdProtocol.nxd();

        nxd.approve(address(_nxdProtocol), nxdDesired);
        dxn.approve(address(_nxdProtocol), dxnDesired);
        _nxdProtocol.createPool(nxdDesired, dxnDesired, to, block.timestamp);

        nxdDXNPair = IUniswapV2PairLocal(
            IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(address(MAINNET_DXN), address(nxd))
        );

        (uint256 res0, uint256 res1,) = nxdDXNPair.getReserves();
        (uint256 resNXD, uint256 resDXN) = nxdDXNPair.token0() == address(nxd) ? (res0, res1) : (res1, res0);

        assertEq(nxd.balanceOf(address(nxdDXNPair)), nxdDesired, "NXD balane should match");
        assertEq(dxn.balanceOf(address(nxdDXNPair)), dxnDesired, "DXN balance should match");

        assertEq(resNXD, nxdDesired, "NXD reserve should match");
        assertEq(resDXN, dxnDesired, "DXN reserve should match");

        assertEq(nxdDXNPair.token0(), address(nxd) > address(dxn) ? address(dxn) : address(nxd), "token0 should match");
        assertEq(nxdDXNPair.token1(), address(nxd) > address(dxn) ? address(nxd) : address(dxn), "token1 should match");

        assertEq(address(_nxdProtocol.v2Oracle()), address(nxd.v2Oracle()), "V2Oracle should match");
        assertEq(address(nxd.uniswapV2Pair()), address(nxdDXNPair), "LP should match");
    }

    function testRevertWhenCreatePoolAlreadyCreated() public {
        vm.expectRevert(NXDProtocol.PoolAlreadyCreated.selector);
        nxdProtocol.createPool(10000 ether, 1000 ether, address(this), block.timestamp);
    }
}
