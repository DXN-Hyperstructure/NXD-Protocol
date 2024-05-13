pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/LPGateway.sol";
import "../src/interfaces/INXDERC20.sol";

contract LPGatewayDeploymentScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Deployer Address: ", deployerAddress);
        vm.startBroadcast(deployerPrivateKey);

        LPGateway lpGateway = new LPGateway();

        console.log("LPGateway Address: ", address(lpGateway));

        INXDERC20 nxd = INXDERC20(0x70536D44820fE3ddd4A2e3eEdbC937b8B9D566C7);
        nxd.updateTaxWhitelist(address(lpGateway), true, true);
    }
}
