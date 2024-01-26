// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

// used for testing voting escrow
contract VotingEscrowMock {
    IERC20 token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function lockedToken() external returns (IERC20) {
        return token;
    }

    function mint(uint256 lockedBalance) external {
        token.transferFrom(msg.sender, address(this), lockedBalance);
    }

    function getVotes(address account) external returns (uint256) {
        return 100 * 10 ** 18;
    }
}
