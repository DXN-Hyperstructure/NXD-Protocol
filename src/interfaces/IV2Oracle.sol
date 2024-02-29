pragma solidity ^0.8.13;

interface IV2Oracle {
    function update() external;

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut);

    function canUpdate() external view returns (bool);
}
