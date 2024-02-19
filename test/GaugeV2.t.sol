// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GaugeV2} from "../src/GaugeV2.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Uint Test For GaugeV2 Contract
 * @author c-n-o-t-e
 * @dev Contract is used to test out GaugeV2 Contract-
 *      by forking the UNREAL chain to interact with....
 *
 * Functionalities Tested:
 */

contract GaugeV2Test is Test {
    error NoClaimableAmount();

    using SafeERC20 for IERC20;

    GaugeV2 public gaugeV2;

    address pearlHolder = 0x95e3664633A8650CaCD2c80A0F04fb56F65DF300;
    address VotingEscrowVesting = 0xA1Bc24d9043C364bF9BAc192ef9a46B8d8f24dCD;

    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    address votingEscrow = 0xee60171b3A81EE2DF0caf0aAd894772B6Acaa772;
    address factory;
    address pool;
    address nonfungiblePositionManager;
    address rewardToken;
    address distribution;
    address internalBribe;
    bool isForPair;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 11000);
        gaugeV2 = new GaugeV2();

        bytes memory init = abi.encodeCall(gaugeV2.initialize, (true));

        ERC1967Proxy mainProxy = new ERC1967Proxy(
            address(main),
            abi.encodeWithSelector(
                RewardsDistributor.initialize.selector,
                votingEscrow
            )
        );

        rewardsDistributor = RewardsDistributor(address(mainProxy));
        rewardsDistributor.setDepositor(address(8));

        vm.startPrank(pearlHolder);
        IERC20(rewardsDistributor.token()).safeTransfer(address(6), 10 ether);
        vm.stopPrank();
    }
}
