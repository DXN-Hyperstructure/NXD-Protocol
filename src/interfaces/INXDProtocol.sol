pragma solidity ^0.8.13;

interface INXDProtocol {
    function depositNoMint(uint256 _amount) external;
    function collectFees() external;
    function stakeOurDXN() external;
}
