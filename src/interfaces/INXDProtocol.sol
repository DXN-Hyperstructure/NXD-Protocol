pragma solidity ^0.8.13;

interface INXDProtocol {
    function depositNoMint(uint256 _amount) external;
    function collectFees() external;
    function stakeOurDXN() external;
    function totalDXNBurned() external view returns (uint256);
    function pendingDXNToStake() external view returns (uint256);
    function totalNXDBurned() external view returns (uint256);
    function totalETHToStakingVault() external view returns (uint256);
}
