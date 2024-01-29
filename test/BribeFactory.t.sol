// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Pearl} from "pearl-token/src/token/Pearl.sol";
import {BribeFactory} from "../src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Uint Test For Rewards Distributor Contract
 * @author c-n-o-t-e
 * @dev Contract is used to test out Rewards Distributor Contract-
 *      by forking the UNREAL chain to interact with voting escrow contract.
 *
 * Functionalities Tested:
 * - Failed scenario initializing the contract.
 * - Failed scenario setting the owner address.
 * - Failed scenario setting amount for reward.
 * - Failed scenario setting the depositor address.
 * - Failed scenario when withdrawing ERC20 from contract.
 * - Failed scenario when caller of the claim() has no reward to claim.
 * - Successfully set the owner address.
 * - Successfully initialize the contract.
 * - Successfully set the depositor address.
 * - Successfully claim rewards from claim().
 * - Successfully check claimable amounts for token IDs.
 * - Successfully withdraw ERC20 tokens from the contract.
 * - Successfully increase locked user tokens when vesting duration is above zero.
 * - Successfully claiming rewards for a given token ID based on its voting power.
 */

contract BribeFactoryTest is Test {
    Pearl public pearl;
    BribeFactory public bribeFactory;

    function setUp() public {
        bribeFactory = new BribeFactory();
        Pearl pearlImpl = new Pearl(block.chainid, address(0));

        bytes memory init = abi.encodeCall(pearlImpl.initialize, (address(8)));
        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearlImpl), init);

        pearl = Pearl(address(pearlProxy));
        address[] memory addr = new address[](1);

        addr[0] = address(pearl);
        init = abi.encodeCall(BribeFactory.initialize, (address(9), addr));

        ERC1967Proxy mainProxy = new ERC1967Proxy(address(bribeFactory), init);
        bribeFactory = BribeFactory(address(mainProxy));
    }

    function test_AssertInitialization() public {
        assertEq(bribeFactory.voter(), address(9));
        assertEq(bribeFactory.defaultRewardToken(0), address(pearl));
        assertEq(bribeFactory.isDefaultRewardToken(address(pearl)), true);
    }
}
