// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidBoxFactory {
    function getBox(address token0, address token1, uint24 fee) external view returns (address);

    function setManager(address manager) external;
    function setBoxManager(address boxManager) external;
    function boxManager() external returns (address boxManager);
}
