// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface sAVAX {
    function getPooledAvaxByShares(uint shareAmount) external returns (uint);
    function balanceOf(address account) external returns (uint);
    function decimals() external view returns (uint);
}
