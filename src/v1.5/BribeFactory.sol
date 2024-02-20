// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {CrossChainFactoryUpgradeable} from "../cross-chain/CrossChainFactoryUpgradeable.sol";
import {Initializable} from "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./Bribe.sol";

contract BribeFactory is Initializable, CrossChainFactoryUpgradeable {
    /**
     * @notice Struct for converting tokens.
     * @param target Target address for conversion.
     * @param data Call data for conversion.
     */
    struct ConvertData {
        address target;
        bytes4 selector;
    }

    address public bribeAdmin;
    address public keeper;
    address public ustb;
    address public voter;

    address public last_bribe;
    address[] internal _bribes;
    address[] public defaultRewardToken;

    mapping(address => bool) public isDefaultRewardToken;

    /**
     * @notice mapping that holds information about convert data for token swaps.
     */
    mapping(address => ConvertData) public convertData;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _mainChainId) CrossChainFactoryUpgradeable(_mainChainId) {
        _disableInitializers();
    }

    function initialize(address _intialOwner, address _voter, address _ustb, address[] calldata defaultRewardTokens)
        public
        initializer
    {
        require(_intialOwner != address(0) && _ustb != address(0), "!zero address");

        __CrossChainFactory_init();
        _transferOwnership(_intialOwner);

        voter = _voter;
        ustb = _ustb;
        bribeAdmin = _intialOwner;
        keeper = _intialOwner;

        // bribe default tokens
        for (uint256 i; i < defaultRewardTokens.length; i++) {
            _pushDefaultRewardToken(defaultRewardTokens[i]);
        }
    }

    modifier onlyBribeAdmin() {
        require(bribeAdmin == _msgSender(), "caller is not the Admin");
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
        if (msg.sender != voter) {
            msg.sender == owner();
        }

        Bribe lastBribe = new Bribe{salt: keccak256(abi.encodePacked(_lzPoolChainId, _pool, _type))}(
            isMainChain, _lzMainChainId, _lzPoolChainId, _owner, voter, address(this), _type
        );

        if (_token0 != address(0)) lastBribe.addReward(_token0);
        if (_token1 != address(0)) lastBribe.addReward(_token1);

        lastBribe.addRewards(defaultRewardToken);

        last_bribe = address(lastBribe);
        _bribes.push(last_bribe);
        return last_bribe;
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
    }

    function setBribeAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "address");
        bribeAdmin = _admin;
    }

    /// @notice set the bribe factory voter
    function setVoter(address _Voter) external onlyOwner {
        require(_Voter != address(0));
        voter = _Voter;
    }

    /// @notice set the bribe factory voter
    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0));
        keeper = _keeper;
    }

    function pushDefaultRewardToken(address _token) external onlyOwner {
        _pushDefaultRewardToken(_token);
    }

    function _pushDefaultRewardToken(address _token) internal {
        require(_token != address(0), "zero address not allowed");
        require(!isDefaultRewardToken[_token], "token already added");
        isDefaultRewardToken[_token] = true;
        defaultRewardToken.push(_token);
    }

    function removeDefaultRewardToken(address _token) external onlyOwner {
        require(isDefaultRewardToken[_token], "not a default reward token");
        for (uint256 i; i < defaultRewardToken.length; i++) {
            if (defaultRewardToken[i] == _token) {
                defaultRewardToken[i] = defaultRewardToken[defaultRewardToken.length - 1];
                defaultRewardToken.pop();
                isDefaultRewardToken[_token] = false;
                break;
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

    /// @notice Add a reward token to a given bribe
    function addRewardToBribe(address _token, address __bribe) external onlyBribeAdmin {
        IBribe(__bribe).addReward(_token);
    }

    /// @notice Add multiple reward token to a given bribe
    function addRewardsToBribe(address[] memory _token, address __bribe) external onlyBribeAdmin {
        for (uint256 i; i < _token.length; i++) {
            IBribe(__bribe).addReward(_token[i]);
        }
    }

    /// @notice Add a reward token to given bribes
    function addRewardToBribes(address _token, address[] memory __bribes) external onlyBribeAdmin {
        for (uint256 i; i < __bribes.length; i++) {
            IBribe(__bribes[i]).addReward(_token);
        }
    }

    /// @notice Add multiple reward tokens to given bribes
    function addRewardsToBribes(address[][] memory _token, address[] memory __bribes) external onlyBribeAdmin {
        for (uint256 i; i < __bribes.length; i++) {
            address _br = __bribes[i];
            for (uint256 k = 0; k < _token.length; k++) {
                IBribe(_br).addReward(_token[i][k]);
            }
        }
    }

    /// @notice set a new voter in given bribes
    function setBribeVoter(address[] memory _bribe, address _voter) external onlyOwner {
        for (uint256 i; i < _bribe.length; i++) {
            IBribe(_bribe[i]).setVoter(_voter);
        }
    }

    /// @notice set a new minter in given bribes
    function setBribeMinter(address[] memory _bribe, address _minter) external onlyOwner {
        for (uint256 i; i < _bribe.length; i++) {
            IBribe(_bribe[i]).setMinter(_minter);
        }
    }

    /// @notice set a new owner in given bribes
    function setBribeOwner(address[] memory _bribe, address _owner) external onlyOwner {
        for (uint256 i; i < _bribe.length; i++) {
            IBribe(_bribe[i]).setOwner(_owner);
        }
    }

    /// @notice recover an ERC20 from bribe contracts.
    function recoverERC20From(address[] memory _bribe, address[] memory _tokens, uint256[] memory _amounts)
        external
        onlyOwner
    {
        require(_bribe.length == _tokens.length, "mismatch len");
        require(_tokens.length == _amounts.length, "mismatch len");

        for (uint256 i; i < _bribe.length; i++) {
            if (_amounts[i] > 0) {
                IBribe(_bribe[i]).emergencyRecoverERC20(_tokens[i], _amounts[i]);
            }
        }
    }

    /// @notice recover an ERC20 from bribe contracts and update.
    function recoverERC20AndUpdateData(address[] memory _bribe, address[] memory _tokens, uint256[] memory _amounts)
        external
        onlyOwner
    {
        require(_bribe.length == _tokens.length, "mismatch len");
        require(_tokens.length == _amounts.length, "mismatch len");

        for (uint256 i; i < _bribe.length; i++) {
            if (_amounts[i] > 0) {
                IBribe(_bribe[i]).emergencyRecoverERC20(_tokens[i], _amounts[i]);
            }
        }
    }
}
