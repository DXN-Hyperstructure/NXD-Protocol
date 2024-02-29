// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDBXenViews {
    /**
     * @dev Unclaimed fees represent the native coin amount that has been allocated
     * to a given account but was not claimed yet.
     *
     * @param account the address to query the unclaimed fees for
     * @return the amount in wei
     */
    function getUnclaimedFees(address account) external view returns (uint256);
}
