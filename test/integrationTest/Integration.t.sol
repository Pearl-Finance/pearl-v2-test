// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Voter} from "../../src/Voter.sol";
import {GaugeV2} from "../../src/GaugeV2.sol";
import {Bribe} from "../../src/v1.5/Bribe.sol";
import {Minter} from "../../src/v1.5/Minter.sol";
import {OFTMockToken} from ".././OFTMockToken.sol";
import {GaugeV2ALM} from "../../src/GaugeV2ALM.sol";
import {LiquidBox} from "../../src/box/LiquidBox.sol";
import {IPearl} from "../../src/interfaces/IPearl.sol";
import {GaugeV2Factory} from "../../src/GaugeV2Factory.sol";
import {BribeFactory} from "../../src/v1.5/BribeFactory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {LiquidBoxFactory} from "../../src/box/LiquidBoxFactory.sol";
import {LiquidBoxManager} from "../../src/box/LiquidBoxManager.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityAmounts} from "../../src/libraries/LiquidityAmounts.sol";
import {IERC721} from "openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VotingEscrow} from "pearl-token/src/governance/VotingEscrow.sol";
import {IPearlV2Factory} from "../../src/interfaces/dex/IPearlV2Factory.sol";
import {EpochController} from "../../src/v1.5/automation/EpochController.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingEscrowVesting} from "pearl-token/src/governance/VotingEscrowVesting.sol";
import {IERC721Receiver} from "openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/dex/INonfungiblePositionManager.sol";
import {LZEndpointMock} from
    "pearl-token/lib/tangible-foundation-contracts/lib/layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

contract IntegrationTest is Test {
    function setUp() public {}
}
