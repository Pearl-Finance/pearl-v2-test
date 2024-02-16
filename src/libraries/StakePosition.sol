// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {FullMath} from "./FullMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";

/// @title Stake
/// @notice Stakes represent an owner address' liquidity between a lower and upper tick boundary
/// @dev Stakes store additional state for tracking fees owed to the Stake
library StakePosition {
    error NP();

    // info stored for each user's Stake
    struct Info {
        address owner;
        uint128 liquidity;
        uint256 rewardsGrowthInsideLastX128;
        uint256 rewardsOwed;
    }

    /// @notice Returns the Info struct of a Stake, given an owner and Stake boundaries
    /// @param self The mapping containing all user Stakes
    /// @param owner The address of the Stake owner
    /// @param tokenId The token id of nft position
    /// @return stake The Stake info struct of the given owners' Stake
    function get(mapping(bytes32 => Info) storage self, address owner, uint256 tokenId)
        internal
        view
        returns (StakePosition.Info storage stake)
    {
        stake = self[keccak256(abi.encodePacked(owner, tokenId))];
    }

    /// @notice Credits accumulated fees to a user's Stake
    /// @param self The individual Stake to update
    /// @param liquidityDelta The change in pool liquidity as a result of the Stake update
    function update(StakePosition.Info storage self, int128 liquidityDelta) internal {
        StakePosition.Info memory _self = self;
        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            if (_self.liquidity <= 0) revert NP(); // disallow pokes for 0 liquidity Stakes
            liquidityNext = _self.liquidity;
        } else {
            liquidityNext = liquidityDelta < 0
                ? _self.liquidity - uint128(-liquidityDelta)
                : _self.liquidity + uint128(liquidityDelta);
        }

        if (liquidityDelta != 0) self.liquidity = liquidityNext;
    }
}
