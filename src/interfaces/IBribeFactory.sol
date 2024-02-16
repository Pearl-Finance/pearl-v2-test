// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error BribeFactory_Token_Already_Added();
error BribeFactory_Zero_Address_Not_Allowed();
error BribeFactory_Tokens_Cannot_Be_The_Same();
error BribeFactory_Not_A_Default_Reward_Token();

interface IBribeFactory {
    function createInternalBribe(address[] memory) external returns (address);

    function createExternalBribe(address[] memory) external returns (address);

    function createBribe(address _owner, address _token0, address _token1, string memory _type)
        external
        returns (address);
}
