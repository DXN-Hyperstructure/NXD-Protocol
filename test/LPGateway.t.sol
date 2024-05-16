import "forge-std/Test.sol";
import "../src/LPGateway.sol";
import "../src/interfaces/INXDERC20.sol";
import "../src/interfaces/IUniswapV2Pair.sol";

contract LPGatewayTest is Test {
    LPGateway public lpGateway;
    INXDERC20 nxd = INXDERC20(0x70536D44820fE3ddd4A2e3eEdbC937b8B9D566C7);
    IERC20 dxn = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F);

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public bob;
    IUniswapV2Pair public dxnNXDPair = IUniswapV2Pair(0x98134CDE70ff7280bb4b9f4eBa2154009f2C13aC);

    function spoofBalance(address token, address account, uint256 balance) public {
        vm.record();
        IERC20(token).balanceOf(account);
        (bytes32[] memory reads,) = vm.accesses(token);
        vm.store(token, reads[0], bytes32(uint256(balance)));
    }

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        lpGateway = new LPGateway();
        vm.prank(nxd.governance());
        nxd.updateTaxWhitelist(address(lpGateway), true, true);
        uint256 bobPrivateKey = 0xa11ce;
        bob = vm.addr(bobPrivateKey);
    }

    function testSetUp() public {}

    function testAddLiquidity() public {
        uint256 amountDXN = 10 ether;
        uint256 amountNXD = 10 ether;
        uint256 amountNXDMin = 0;
        uint256 amountDXNMin = 0;
        address to = address(bob);
        uint256 deadline = block.timestamp + 1000;
        vm.startPrank(bob);

        spoofBalance(address(dxn), address(bob), amountDXN);
        spoofBalance(address(nxd), address(bob), amountNXD);

        nxd.approve(address(lpGateway), amountNXD);
        dxn.approve(address(lpGateway), amountDXN);

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            lpGateway.addLiquidity(address(dxn), amountNXD, amountDXN, amountNXDMin, amountDXNMin, to, deadline);

        if (amountNXD > amountA) {
            assertEq(nxd.balanceOf(bob), amountNXD - amountA, "NXD balance mismatch");
        }
        if (amountDXN > amountB) {
            assertEq(dxn.balanceOf(bob), amountDXN - amountB, "DXN balance mismatch");
        }

        assertEq(dxnNXDPair.balanceOf(bob), liquidity, "Liquidity mismatch");
    }

    function testFuzz_addLiquidity(uint256 amountDXN, uint256 amountNXD) public {
        vm.assume(amountDXN <= 550000 ether && amountDXN > 0.01 ether);
        vm.assume(amountNXD <= 750000 ether && amountNXD > 0.01 ether);
        uint256 amountNXDMin = 0;
        uint256 amountDXNMin = 0;
        address to = address(bob);
        uint256 deadline = block.timestamp + 1000;
        vm.startPrank(bob);

        spoofBalance(address(dxn), address(bob), amountDXN);
        spoofBalance(address(nxd), address(bob), amountNXD);

        nxd.approve(address(lpGateway), amountNXD);
        dxn.approve(address(lpGateway), amountDXN);

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            lpGateway.addLiquidity(address(dxn), amountNXD, amountDXN, amountNXDMin, amountDXNMin, to, deadline);

        if (amountNXD > amountA) {
            assertEq(nxd.balanceOf(bob), amountNXD - amountA, "NXD balance mismatch");
        }
        if (amountDXN > amountB) {
            assertEq(dxn.balanceOf(bob), amountDXN - amountB, "DXN balance mismatch");
        }

        assertEq(dxnNXDPair.balanceOf(bob), liquidity, "Liquidity mismatch");
    }

    function testRemoveLiquidity() public {
        uint256 amountDXN = 10 ether;
        uint256 amountNXD = 10 ether;
        uint256 amountNXDMin = 0;
        uint256 amountDXNMin = 0;
        address to = address(bob);
        uint256 deadline = block.timestamp + 1000;
        vm.startPrank(bob);

        spoofBalance(address(dxn), address(bob), amountDXN);
        spoofBalance(address(nxd), address(bob), amountNXD);

        nxd.approve(address(lpGateway), amountNXD);
        dxn.approve(address(lpGateway), amountDXN);

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            lpGateway.addLiquidity(address(dxn), amountNXD, amountDXN, amountNXDMin, amountDXNMin, to, deadline);

        uint256 dxnBalanceBeforeRemove = dxn.balanceOf(bob);
        uint256 nxdBalanceBeforeRemove = nxd.balanceOf(bob);

        dxnNXDPair.approve(address(lpGateway), liquidity);

        (uint256 amountNXDRemoved, uint256 amountDXNRemoved) =
            lpGateway.removeLiquidity(address(dxn), liquidity, amountNXDMin, amountDXNMin, to, deadline);

        assertEq(dxnNXDPair.balanceOf(bob), 0, "Liquidity mismatch");
        assertEq(dxn.balanceOf(bob) - dxnBalanceBeforeRemove, amountDXNRemoved, "DXN balance mismatch");
        assertEq(nxd.balanceOf(bob) - nxdBalanceBeforeRemove, amountNXDRemoved, "NXD balance mismatch");
    }
}
