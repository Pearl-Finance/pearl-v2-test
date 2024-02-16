// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBribeFactory {
    error BribeFactory_Mismatch_Length();
    error BribeFactory_Token_Already_Added();
    error BribeFactory_Zero_Address_Not_Allowed();
    error BribeFactory_Tokens_Cannot_Be_The_Same();
    error BribeFactory_Not_A_Default_Reward_Token();

    function setVoter(address _Voter) external;

    function pushDefaultRewardToken(address _token) external;

    function removeDefaultRewardToken(address _token) external;

    function addRewardToBribe(address _token, address __bribe) external;

    function setBribeOwner(address[] memory _bribe, address _owner) external;

    function setBribeVoter(address[] memory _bribe, address _voter) external;

    function setBribeMinter(address[] memory _bribe, address _minter) external;

    function addRewardsToBribe(address[] memory _token, address __bribe) external;

    function addRewardToBribes(address _token, address[] memory __bribes) external;

    function initialize(address _voter, address[] calldata defaultRewardTokens) external;

    function addRewardsToBribes(address[][] memory _token, address[] memory __bribes) external;

    function recoverERC20From(address[] memory _bribe, address[][] memory _tokens, uint256[][] memory _amounts)
        external;

    function recoverERC20AndUpdateData(address[] memory _bribe, address[][] memory _tokens, uint256[][] memory _amounts)
        external;

    function createBribe(address _owner, address _token0, address _token1, string memory _type)
        external
        returns (address);
}
