// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IBribeFactory} from "../interfaces/IBribeFactory.sol";
import {Bribe, IBribe} from "./Bribe.sol";

contract BribeFactory is IBribeFactory, AccessControlUpgradeable {
    bytes32 public constant BRIBE_ADMIN_ROLE = keccak256("BRIBE_ADMIN");

    address public last_bribe;
    address[] internal _bribes;
    address public voter;

    address[] public defaultRewardToken;

    mapping(address => bool) public isDefaultRewardToken;

    constructor() {}

    function initialize(address _voter, address[] calldata defaultRewardTokens) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(BRIBE_ADMIN_ROLE, _msgSender());
        voter = _voter;

        // bribe default tokens
        for (uint256 i = 0; i < defaultRewardTokens.length; i++) {
            _pushDefaultRewardToken(defaultRewardTokens[i]);
        }

        // emit event
    }

    /// @notice create a bribe contract
    /// @dev    _owner must be teamMultisig
    function createBribe(address _owner, address _token0, address _token1, string memory _type)
        external
        returns (address)
    {
        if (msg.sender != voter) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }

        if (_token0 != address(0) || _token1 != address(0)) {
            if (_token0 == _token1) {
                revert BribeFactory_Tokens_Cannot_Be_The_Same();
            }
        }

        Bribe lastBribe = new Bribe(_owner, voter, address(this), _type);

        if (_token0 != address(0)) lastBribe.addReward(_token0);
        if (_token1 != address(0)) lastBribe.addReward(_token1);

        // check if token0 and token1 is not the same
        // if an address is 0 that means no address for reward?
        // must a bribe have a reward token added upon deployment?
        // that means two bribes can have same tokens?

        lastBribe.addRewards(defaultRewardToken); // default rewards token should be added before other reward tokens.

        last_bribe = address(lastBribe);
        _bribes.push(last_bribe);
        return last_bribe;

        // emit event
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice set the bribe factory voter
    function setVoter(address _Voter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_Voter != address(0));
        voter = _Voter;

        // emit event
    }

    function pushDefaultRewardToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pushDefaultRewardToken(_token);
        // emit event
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

    function removeDefaultRewardToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isDefaultRewardToken[_token]) {
            revert BribeFactory_Not_A_Default_Reward_Token();
        }

        uint256 i = 0;
        for (i; i < defaultRewardToken.length; i++) {
            if (defaultRewardToken[i] == _token) {
                defaultRewardToken[i] = defaultRewardToken[defaultRewardToken.length - 1];
                defaultRewardToken.pop();
                isDefaultRewardToken[_token] = false;
                break;
            }
        }
        // emit event
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER or BRIBE ADMIN
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice Add a reward token to a given bribe
    function addRewardToBribe(address _token, address __bribe) external onlyRole(BRIBE_ADMIN_ROLE) {
        IBribe(__bribe).addReward(_token);
    }

    /// @notice Add multiple reward token to a given bribe
    function addRewardsToBribe(address[] memory _token, address __bribe) external onlyRole(BRIBE_ADMIN_ROLE) {
        uint256 i = 0;
        for (i; i < _token.length; i++) {
            IBribe(__bribe).addReward(_token[i]);
        }
    }

    /// @notice Add a reward token to given bribes
    function addRewardToBribes(address _token, address[] memory __bribes) external onlyRole(BRIBE_ADMIN_ROLE) {
        uint256 i = 0;
        for (i; i < __bribes.length; i++) {
            IBribe(__bribes[i]).addReward(_token);
        }
    }

    /// @notice Add multiple reward tokens to given bribes
    function addRewardsToBribes(address[][] memory _token, address[] memory __bribes)
        external
        onlyRole(BRIBE_ADMIN_ROLE)
    {
        uint256 i = 0;
        uint256 k;
        for (i; i < __bribes.length; i++) {
            address _br = __bribes[i];
            for (k = 0; k < _token[i].length; k++) {
                IBribe(_br).addReward(_token[i][k]);
            }
        }
    }

    /// @notice set a new voter in given bribes
    function setBribeVoter(address[] memory _bribe, address _voter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 i = 0;
        for (i; i < _bribe.length; i++) {
            IBribe(_bribe[i]).setVoter(_voter);
        }
    }

    /// @notice set a new minter in given bribes
    function setBribeMinter(address[] memory _bribe, address _minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 i = 0;
        for (i; i < _bribe.length; i++) {
            IBribe(_bribe[i]).setMinter(_minter);
        }
    }

    /// @notice set a new owner in given bribes
    function setBribeOwner(address[] memory _bribe, address _owner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 i = 0;
        for (i; i < _bribe.length; i++) {
            IBribe(_bribe[i]).setOwner(_owner);
        }
    }

    /// @notice recover an ERC20 from bribe contracts.
    function recoverERC20From(address[] memory _bribe, address[][] memory _tokens, uint256[][] memory _amounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 i = 0;
        uint256 k;
        for (i; i < _bribe.length; i++) {
            if (_tokens[i].length != _amounts[i].length) {
                revert BribeFactory_Mismatch_Length();
            }
            address _br = _bribe[i];
            for (k = 0; k < _tokens[i].length; k++) {
                if (_amounts[i][k] > 0) {
                    IBribe(_br).emergencyRecoverERC20(_tokens[i][k], _amounts[i][k]);
                }
            }
        }
    }

    /// @notice recover an ERC20 from bribe contracts and update.
    function recoverERC20AndUpdateData(address[] memory _bribe, address[][] memory _tokens, uint256[][] memory _amounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 i = 0;
        uint256 k;
        for (i; i < _bribe.length; i++) {
            if (_tokens[i].length != _amounts[i].length) {
                revert BribeFactory_Mismatch_Length();
            }
            address _br = _bribe[i];
            for (k = 0; k < _tokens[i].length; k++) {
                if (_amounts[i][k] > 0) {
                    IBribe(_br).recoverERC20AndUpdateData(_tokens[i][k], _amounts[i][k]);
                }
            }
        }
    }
}
