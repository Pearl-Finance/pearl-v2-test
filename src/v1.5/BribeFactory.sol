// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ClonesUpgradeable} from "openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {CrossChainFactoryUpgradeable} from "../cross-chain/CrossChainFactoryUpgradeable.sol";
import {Initializable} from "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IBribe} from "../interfaces/IBribe.sol";

contract BribeFactory is Initializable, CrossChainFactoryUpgradeable {
    using ClonesUpgradeable for address;

    /**
     * @notice Struct for converting tokens.
     * @param target Target address for conversion.
     * @param data Call data for conversion.
     */
    struct ConvertData {
        address target;
        bytes4 selector;
    }

    address public bribeImplementation;
    address public bribeAdmin;
    address public keeper;
    address public ustb;
    address public voter;

    address public recentBribe;
    address[] internal _bribes;
    address[] public defaultRewardToken;

    mapping(address => bool) public isDefaultRewardToken;

    /**
     * @notice mapping that holds information about convert data for token swaps.
     */
    mapping(address => ConvertData) public convertData;

    event AdminChanged(address indexed admin);
    event VoterChanged(address indexed voter);
    event KeeperChanged(address indexed keeper);
    event BibeImplementationChanged(address indexed bribeImplementation);
    event BribeCreated(address indexed owner, address token0, address token1, string bribeType);
    event ConvertDataSet(address indexed target, bytes4 selector);

    error BribeFactory_Mismatch_Length();
    error BribeFactory_Caller_Is_Not_Admin();
    error BribeFactory_Token_Already_Added();
    error BribeFactory_Zero_Address_Not_Allowed();
    error BribeFactory_Tokens_Cannot_Be_The_Same();
    error BribeFactory_Not_A_Default_Reward_Token();
    error BribeFactory_NotAuthorized();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _mainChainId) CrossChainFactoryUpgradeable(_mainChainId) {
        _disableInitializers();
    }

    function initialize(
        address _intialOwner,
        address _bribeImplementation,
        address _voter,
        address _ustb,
        address[] calldata defaultRewardTokens
    ) public initializer {
        if (_intialOwner == address(0) || _bribeImplementation == address(0) || _ustb == address(0)) {
            revert BribeFactory_Zero_Address_Not_Allowed();
        }

        __CrossChainFactory_init();
        _transferOwnership(_intialOwner);

        voter = _voter;
        ustb = _ustb;
        bribeAdmin = _intialOwner;
        keeper = _intialOwner;
        bribeImplementation = _bribeImplementation;

        // bribe default tokens
        for (uint256 i; i < defaultRewardTokens.length;) {
            _pushDefaultRewardToken(defaultRewardTokens[i]);
            unchecked {
                i++;
            }
        }
    }

    modifier onlyBribeAdmin() {
        if (bribeAdmin != _msgSender()) {
            revert BribeFactory_Caller_Is_Not_Admin();
        }
        _;
    }

    /// @notice create a bribe contract
    /// @dev _owner must be teamMultisig
    function createBribe(
        uint16 _lzMainChainId,
        uint16 _lzPoolChainId,
        address _pool,
        address _owner,
        address _token0,
        address _token1,
        string memory _type
    ) external returns (address) {
        if (msg.sender != voter && msg.sender != owner()) {
            revert BribeFactory_NotAuthorized();
        }

        bytes32 salt = keccak256(abi.encodePacked(_lzPoolChainId, _pool, _type));
        address lastBribe = bribeImplementation.cloneDeterministic(salt);

        IBribe(lastBribe).initialize(isMainChain, _lzMainChainId, _lzPoolChainId, _owner, voter, address(this), _type);

        if (_token0 != address(0) || _token1 != address(0)) {
            if (_token0 == _token1) {
                revert BribeFactory_Tokens_Cannot_Be_The_Same();
            }
        }

        IBribe(lastBribe).addRewards(defaultRewardToken);

        if (_token0 != address(0)) IBribe(lastBribe).addReward(_token0);
        if (_token1 != address(0)) IBribe(lastBribe).addReward(_token1);

        recentBribe = lastBribe;
        _bribes.push(lastBribe);

        emit BribeCreated(_owner, _token0, _token1, _type);
        return lastBribe;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /**
     * @notice Data for converting any token to USTB (reward token).
     * @dev Owner sets address and selector for function when swap from token to
     * reward token is performed.
     * Used by contract owner.
     * @param _target The address to call
     * @param _selector Function that is doing the conversion/swap
     */
    function setConvertData(address _target, bytes4 _selector) external onlyOwner {
        ConvertData storage _convertData = convertData[_target];
        _convertData.target = _target;
        _convertData.selector = _selector;
        emit ConvertDataSet(_target, _selector);
    }

    function setBribeAdmin(address _admin) external onlyOwner {
        if (_admin == address(0)) {
            revert BribeFactory_Zero_Address_Not_Allowed();
        }
        bribeAdmin = _admin;
        emit AdminChanged(_admin);
    }

    /// @notice set the bribe factory voter
    function setVoter(address _voter) external onlyOwner {
        if (_voter == address(0)) {
            revert BribeFactory_Zero_Address_Not_Allowed();
        }
        voter = _voter;
        emit VoterChanged(_voter);
    }

    /// @notice set the bribe factory keeper for bridging bribes
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) {
            revert BribeFactory_Zero_Address_Not_Allowed();
        }
        keeper = _keeper;
        emit KeeperChanged(_keeper);
    }

    function pushDefaultRewardToken(address _token) external onlyOwner {
        _pushDefaultRewardToken(_token);
    }

    function _pushDefaultRewardToken(address _token) internal {
        if (_token == address(0)) {
            revert BribeFactory_Zero_Address_Not_Allowed();
        }
        if (isDefaultRewardToken[_token]) {
            revert BribeFactory_Token_Already_Added();
        }

        isDefaultRewardToken[_token] = true;
        defaultRewardToken.push(_token);
    }

    function removeDefaultRewardToken(address _token) external onlyOwner {
        if (!isDefaultRewardToken[_token]) {
            revert BribeFactory_Not_A_Default_Reward_Token();
        }

        uint256 length = defaultRewardToken.length;
        address[] memory _defaultRewardToken = new address[](length);
        _defaultRewardToken = defaultRewardToken;

        for (uint256 i; i < length;) {
            if (_defaultRewardToken[i] == _token) {
                if (_defaultRewardToken[i] != _defaultRewardToken[_defaultRewardToken.length - 1]) {
                    _defaultRewardToken[i] = _defaultRewardToken[_defaultRewardToken.length - 1];
                }

                defaultRewardToken = _defaultRewardToken;
                defaultRewardToken.pop();

                isDefaultRewardToken[_token] = false;
                break;
            }

            unchecked {
                i++;
            }
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER or BRIBE ADMIN
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /**
     * @notice Sets a new bribe implementation address
     * @dev This function can only be called by the owner of the contract.
     * @param _bribeImplementation The address of the new bribe implementation.
     */
    function setBribeImplementation(address _bribeImplementation) external onlyOwner {
        require(_bribeImplementation != address(0), "!zero address");
        bribeImplementation = _bribeImplementation;
        emit BibeImplementationChanged(_bribeImplementation);
    }

    /// @notice Add a reward token to a given bribe
    function addRewardToBribe(address _token, address __bribe) external onlyBribeAdmin {
        IBribe(__bribe).addReward(_token);
    }

    /// @notice Add multiple reward token to a given bribe
    function addRewardsToBribe(address[] memory _token, address __bribe) external onlyBribeAdmin {
        for (uint256 i; i < _token.length;) {
            IBribe(__bribe).addReward(_token[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Add a reward token to given bribes
    function addRewardToBribes(address _token, address[] memory __bribes) external onlyBribeAdmin {
        for (uint256 i; i < __bribes.length;) {
            IBribe(__bribes[i]).addReward(_token);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Add multiple reward tokens to given bribes
    function addRewardsToBribes(address[][] memory _token, address[] memory __bribes) external onlyBribeAdmin {
        for (uint256 i; i < __bribes.length;) {
            address _br = __bribes[i];
            for (uint256 k = 0; k < _token[i].length;) {
                IBribe(_br).addReward(_token[i][k]);
                unchecked {
                    k++;
                }
            }
            unchecked {
                i++;
            }
        }
    }

    /// @notice set a new voter in given bribes
    function setBribeVoter(address[] memory _bribe, address _voter) external onlyOwner {
        for (uint256 i; i < _bribe.length;) {
            IBribe(_bribe[i]).setVoter(_voter);
            unchecked {
                i++;
            }
        }
    }

    /// @notice set a new minter in given bribes
    function setBribeMinter(address[] memory _bribe, address _minter) external onlyOwner {
        for (uint256 i; i < _bribe.length;) {
            IBribe(_bribe[i]).setMinter(_minter);
            unchecked {
                i++;
            }
        }
    }

    /// @notice set a new owner in given bribes
    function setBribeOwner(address[] memory _bribe, address _owner) external onlyOwner {
        for (uint256 i; i < _bribe.length;) {
            IBribe(_bribe[i]).setOwner(_owner);
            unchecked {
                i++;
            }
        }
    }

    /// @notice recover an ERC20 from bribe contracts.
    function recoverERC20From(
        address[] memory _bribe,
        address[][] memory _tokens,
        uint256[][] memory _amounts,
        bool isRecoverERC20AndUpdateData
    ) external onlyOwner {
        for (uint256 i = 0; i < _bribe.length;) {
            if (_tokens[i].length != _amounts[i].length) {
                revert BribeFactory_Mismatch_Length();
            }
            bytes memory data = abi.encode(_tokens[i], _amounts[i]);
            IBribe(_bribe[i]).emergencyRecoverERC20AndRecoverData(data, isRecoverERC20AndUpdateData);
            unchecked {
                i++;
            }
        }
    }
}
