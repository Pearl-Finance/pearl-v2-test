// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/ICrossChainFactory.sol";

interface IBribeFactory is ICrossChainFactory {
    /**
     * @notice Struct for converting tokens.
     * @param target Target address for conversion.
     * @param selector Function selector for the conversion.
     */
    struct ConvertData {
        address target;
        bytes4 selector;
    }

    /**
     * @notice Use to initialize the BribeFactory contract.
     * @param _intialOwner owner of contract after deployment.
     * @param _voter address of the voter contract.
     * @param _ustb address of the ustb contract.
     * @param defaultRewardTokens array of default reward tokens.
     */
    function initialize(address _intialOwner, address _voter, address _ustb, address[] calldata defaultRewardTokens)
        external;

    /**
     * @notice Sets a new voter contract address.
     * @param _Voter address of the new voter contract.
     */
    function setVoter(address _Voter) external;

    /**
     * @notice Add token to an array of default reward tokens.
     *         Only called owner of contract.
     * @param _token address of token to be added to default reward token.
     */
    function pushDefaultRewardToken(address _token) external;

    /**
     * @notice Remove token from an array of default reward tokens.
     *         Only called owner of contract.
     * @param _token address of token to be removed from default reward tokens.
     */
    function removeDefaultRewardToken(address _token) external;

    /**
     * @notice Add reward token to a bribe contract.
     * @param _token reward token to be add to __bribe.
     * @param __bribe address of bribe contract.
     */
    function addRewardToBribe(address _token, address __bribe) external;

    /**
     * @notice Set owner address for an array of bribe contracts.
     * @param _bribe array of bribe contract addresses.
     * @param _owner new owner address for an array of bribe contracts.
     */
    function setBribeOwner(address[] memory _bribe, address _owner) external;

    /**
     * @notice Set voter address for an array of bribe contracts.
     * @param _bribe array of bribe contract addresses.
     * @param _voter new voter address for an array of bribe contracts.
     */
    function setBribeVoter(address[] memory _bribe, address _voter) external;

    /**
     * @notice Set minter address for an array of bribe contracts.
     * @param _bribe array of bribe contract addresses.
     * @param _minter new minter address for an array of bribe contracts.
     */
    function setBribeMinter(address[] memory _bribe, address _minter) external;

    /**
     * @notice Add an array of reward token addresses for a bribe contract.
     * @param _token array of reward token addresses.
     * @param __bribe address of bribe contract to be updated.
     */
    function addRewardsToBribe(address[] memory _token, address __bribe) external;

    /**
     * @notice Add reward token address to an array of bribe contracts.
     * @param _token reward token address.
     * @param __bribes array of bribe contract addresses.
     */
    function addRewardToBribes(address _token, address[] memory __bribes) external;

    /**
     * @notice Add an array of reward token addresses to an array of bribe contracts.
     * @param _token  array of reward token addresses.
     * @param __bribes array of bribe contract addresses.
     */
    function addRewardsToBribes(address[][] memory _token, address[] memory __bribes) external;

    /**
     * @notice Recover an array of token funds from an array of bribe contract.
     * @param _bribe  array of bribe contract addresses.
     * @param _tokens  array of token addresses.
     * @param _amounts array of amounts to recovered.
     * @param isRecoverERC20AndUpdateData indicator to updated given bribe or not while recovering some ERC20 from the contract.
     */
    function recoverERC20From(
        address[] memory _bribe,
        address[][] memory _tokens,
        uint256[][] memory _amounts,
        bool isRecoverERC20AndUpdateData
    ) external;

    /**
     * @notice Creates a new Bribe contract
     * @param _lzMainChainId  L1 chain ID.
     * @param _lzPoolChainId  L2 chain ID.
     * @param _pool pearl pool address.
     * @param _owner owner of contract.
     * @param _token0 first reward token address.
     * @param _token1 first reward token address..
     * @param _type type of bribe to be created.
     */
    function createBribe(
        uint16 _lzMainChainId,
        uint16 _lzPoolChainId,
        address _pool,
        address _owner,
        address _token0,
        address _token1,
        string memory _type
    ) external returns (address);

    /**
     * @notice Retrieves the address of the keeper.
     * @return Address of the keeper contract.
     */
    function keeper() external view returns (address);

    /**
     * @notice Retrieves the address of the USTB (US T-BILL).
     * @return Address of the USTB contract.
     */
    function ustb() external view returns (address);

    /**
     * @notice Retrieves the main chain ID.
     * @return Main chain ID.
     */
    function mainChainId() external view returns (uint16);

    /**
     * @notice Retrieves the conversion data for a target address.
     * @param target Target address for conversion.
     * @return ConvertData struct containing the target and function selector.
     */
    function convertData(address target) external view returns (ConvertData memory);
}
