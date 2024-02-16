// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISolidlyAutoBriber {
    function notify(address token, uint256 rebaseIndex) external returns (bool);
}
