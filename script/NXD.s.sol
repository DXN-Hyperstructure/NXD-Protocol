// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/V2Oracle.sol";
import "../src/V3Oracle.sol";
import "../src/NXDProtocol.sol";
import "../src/Vesting.sol";
import "../src/dbxen/DBXenViews.sol";
import "../src/dbxen/DBXen.sol";
import "../src/NXDERC20.sol";
import "../src/interfaces/INXDStakingVault.sol";

contract NXDScript is Script {
    address public UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    DBXen public DBXEN = DBXen(0xF5c80c305803280B587F8cabBcCdC4d9BF522AbD);
    IERC20 public constant DXN = IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F); // DXN token
    DBXenViews public dbxenViews;
    uint256 public constant INITIAL_NXD_LP_AMOUNT = 10000 ether; // 10000 NXD tokens
    uint256 public constant DXN_DESIRED = 1 ether;
    NXDERC20 public nxd;
    INXDStakingVault public nxdStakingVault;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        vm.label(address(DXN), "DXN");
        address deployerAddress = vm.addr(deployerPrivateKey);

        V3Oracle v3Oracle = new V3Oracle();
        dbxenViews = new DBXenViews(DBXEN);

        Vesting nxdVesting = new Vesting();

        NXDProtocol nxdProtocol = new NXDProtocol(
            INITIAL_NXD_LP_AMOUNT,
            address(DBXEN),
            address(dbxenViews),
            address(v3Oracle),
            deployerAddress,
            address(nxdVesting)
        );

        nxd = nxdProtocol.nxd();
        nxdStakingVault = INXDStakingVault(address(nxdProtocol.nxdStakingVault()));
        // Whitelist NXD stakers to get ETH rewards
        nxdStakingVault.add(100, nxd, false, true);

        console.log("NXD Token: ", address(nxd));

        // Create LP
        DXN.approve(address(nxdProtocol), DXN_DESIRED);
        nxd.approve(address(nxdProtocol), INITIAL_NXD_LP_AMOUNT);
        nxdProtocol.createPool(INITIAL_NXD_LP_AMOUNT, DXN_DESIRED, deployerAddress, block.timestamp);

        console.log("DBXen Views Deployed At: ", address(dbxenViews));
        console.log("NXD Protocol Deployed At: ", address(nxdProtocol));
        console.log("NXD Staking Vault Deployed At: ", address(nxdStakingVault));
        console.log("V2 Oracle Deployed At: ", address(nxdProtocol.v2Oracle()));
        console.log("V3 Oracle Deployed At: ", address(v3Oracle));
    }
}
