pragma solidity >=0.8.0;

import "./NXD.Shared.t.sol";
import "../src/TaxRecipient.sol";

contract TaxRecipientTest is NXDShared {
    TaxRecipient public taxRecipient;

    function setUp() public {
        taxRecipient = nxd.taxRecipient();
    }

    function testRevertWhenUnauthorizedSetUniV2Pair() public {
        vm.startPrank(bob);
        vm.expectRevert(TaxRecipient.OnlyNXD.selector);
        taxRecipient.setUniswapV2Pair(address(0x0));
    }

    function testRevertWhenUnauthorizedHandleTax() public {
        vm.startPrank(bob);
        vm.expectRevert(TaxRecipient.OnlyNXD.selector);
        taxRecipient.handleTax();
    }
}
