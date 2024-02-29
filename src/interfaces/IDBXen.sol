pragma solidity ^0.8.13;

interface IDBXen {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function withdraw(uint256 amount) external;

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function claimFees() external;

    function claimRewards() external;

    function stake(uint256 amount) external;

    function accAccruedFees(address account) external view returns (uint256);

    function accRewards(address account) external view returns (uint256);

    function accWithdrawableStake(
        address account
    ) external view returns (uint256);
}
