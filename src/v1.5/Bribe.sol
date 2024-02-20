// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/contracts/token/ERC20/IERC20.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "openzeppelin/contracts/access/Ownable.sol";
import "openzeppelin/contracts/utils/math/Math.sol";
import "openzeppelin/contracts/utils/math/SafeMath.sol";
import {IOFT} from "layerzerolabs/token/oft/v1/interfaces/IOFT.sol";

import "../interfaces/IBribeFactory.sol";
import "../interfaces/IBribe.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IVoter.sol";
import "../interfaces/IVotingEscrow.sol";
import "../Epoch.sol";

contract Bribe is IBribe, ReentrancyGuard {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 10 ** 36;
    uint256 public firstBribeTimestamp;

    /* ========== STATE VARIABLES ========== */

    bool public isMainChain;

    uint16 public lzMainChainId;
    uint16 public lzPoolChainId;

    uint64 nonce;
    // uint256 public mainChainId;

    address public owner;
    address public ustb;
    address public ve;
    address public voter;
    address public minter;
    address public bribeFactory;
    address[] public rewardTokens;

    string public TYPE;

    mapping(address => mapping(uint256 => IBribe.Reward)) private _rewardData; // token -> startTimestamp -> Reward
    mapping(address => uint256) _reserves;
    mapping(address => bool) public isRewardToken;
    mapping(uint64 => uint256) public rewardCredited;

    mapping(address account => mapping(address token => uint256)) public userRewardPerTokenPaid;
    mapping(address account => mapping(address token => uint256)) public userTimestamp;

    mapping(uint256 => uint256) public _totalSupply;
    mapping(address account => mapping(uint256 timestamp => uint256)) private _balances;

    /* ========== EVENTS ========== */

    event RewardCredited(uint64 nonceId, uint256 reward);
    event RewardAdded(uint64 nonceId, address rewardToken, uint256 reward, uint256 startTimestamp);
    event Staked(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);

    event Recovered(address token, uint256 amount);

    /**
     * @notice Event emitted when a token is converted.
     * @param token Token that was converted.
     * @param amount Amount of token that was converted.
     * @param amountOut Amount of reward token received.
     */
    event TokenConverted(address indexed token, uint256 amount, uint256 amountOut);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        bool _isMainChain,
        uint16 _lzMainChainId,
        uint16 _lzPoolChainId,
        address _owner,
        address _voter,
        address _bribeFactory,
        string memory _type
    ) {
        require(_bribeFactory != address(0) && _voter != address(0) && _owner != address(0), "!zero address");

        require(_lzMainChainId != 0 && _lzPoolChainId != 0, "!zero lz chain id");

        require(
            (_isMainChain && _lzMainChainId == _lzPoolChainId) || (!isMainChain && _lzMainChainId != _lzPoolChainId),
            "!lzPoolChain"
        );

        isMainChain = _isMainChain;
        lzMainChainId = _lzMainChainId;
        lzPoolChainId = _lzPoolChainId;

        // minter is only available on the main chain
        if (_isMainChain) {
            minter = IVoter(_voter).minter();
            require(minter != address(0));
            ve = IVoter(_voter)._ve();
        }

        voter = _voter;
        bribeFactory = _bribeFactory;
        firstBribeTimestamp = 0;
        owner = _owner;

        ustb = IBribeFactory(bribeFactory).ustb();
        TYPE = _type;
    }

    /* ========== MODIFIERS ========== */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyRole() {
        _checkRole();
        _;
    }

    modifier onlyKeeper() {
        _checkKeeper();
        _;
    }

    modifier isAllowed() {
        _checkAllowed();
        _;
    }

    function _checkOwner() internal view {
        require(owner == msg.sender, "caller is not the owner");
    }

    function _checkRole() internal view {
        require((msg.sender == owner || msg.sender == bribeFactory), "permission is denied!");
    }

    function _checkKeeper() internal view {
        require(msg.sender == IBribeFactory(bribeFactory).keeper(), "!keeper");
    }

    function _checkAllowed() internal view {
        require(isMainChain, "!mainChain");
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _deposit(uint256 amount, address account) external nonReentrant isAllowed {
        require(amount > 0, "Cannot stake 0");
        require(msg.sender == voter);
        uint256 _startTimestamp = getNextEpochStart();
        uint256 _oldSupply = _totalSupply[_startTimestamp];
        _totalSupply[_startTimestamp] = _oldSupply + amount;
        _balances[account][_startTimestamp] = _balances[account][_startTimestamp] + amount;
        emit Staked(account, amount);
    }

    function _withdraw(uint256 amount, address account) public nonReentrant isAllowed {
        require(amount > 0, "Cannot withdraw 0");
        require(msg.sender == voter);
        uint256 _startTimestamp = getNextEpochStart();
        // incase of bribe contract reset in gauge proxy
        if (amount <= _balances[account][_startTimestamp]) {
            uint256 _oldSupply = _totalSupply[_startTimestamp];
            uint256 _oldBalance = _balances[account][_startTimestamp];
            _totalSupply[_startTimestamp] = _oldSupply - amount;
            _balances[account][_startTimestamp] = _oldBalance - amount;
            emit Withdrawn(account, amount);
        }
    }

    function _earned(address account, address _rewardToken, uint256 _timestamp) internal view returns (uint256) {
        uint256 _balance = balanceOfAt(account, _timestamp);
        if (_balance == 0) {
            return 0;
        } else {
            uint256 _rewardPerToken = rewardPerToken(_rewardToken, _timestamp);
            uint256 _rewards = _rewardPerToken.mulDiv(_balance, PRECISION);
            return _rewards;
        }
    }

    /**
     * @notice Converts a specific token to USTB.
     * @dev This function is used to convert any token to USTB. It contains the check
     * to verify that the target address and selector are correct to avoid exploits.
     * @param _tokenIn Token to convert.
     * @param _tokenOut Token to receive.
     * @param _amount Amount to convert.
     * @param _target Target address for conversion.
     * @param _data Call data for conversion.
     * @return _amountOut Amount received.
     */
    function _convertToken(address _tokenIn, address _tokenOut, uint256 _amount, address _target, bytes calldata _data)
        internal
        returns (uint256 _amountOut)
    {
        uint256 _before = IERC20(_tokenOut).balanceOf(address(this));
        IBribeFactory.ConvertData memory _convertData = IBribeFactory(bribeFactory).convertData(_target);
        // check if this is a pre-approved contract for swapping/converting
        require(_convertData.target == _target, "invalid target");
        require(_convertData.selector == bytes4(_data[0:4]), "invalid selector");
        IERC20(_tokenIn).forceApprove(_target, 0);
        IERC20(_tokenIn).forceApprove(_target, _amount);
        (bool _success,) = _target.call(_data);
        require(_success, "low swap level call failed");
        _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _before;
    }

    function _addBribeForEpoch(uint64 _nonceId, address _rewardsToken, uint256 reward) internal {
        _reserves[_rewardsToken] += reward;

        uint256 _startTimestamp = getNextEpochStart();
        if (firstBribeTimestamp == 0) {
            firstBribeTimestamp = _startTimestamp;
        }

        uint256 _lastReward = _rewardData[_rewardsToken][_startTimestamp].rewardsPerEpoch;

        _rewardData[_rewardsToken][_startTimestamp].rewardsPerEpoch = _lastReward + reward;
        _rewardData[_rewardsToken][_startTimestamp].lastUpdateTime = block.timestamp;
        _rewardData[_rewardsToken][_startTimestamp].periodFinish = _startTimestamp + EPOCH_DURATION;

        emit RewardAdded(_nonceId, _rewardsToken, reward, _startTimestamp);
    }

    function _getReward(address account, address[] calldata tokens) internal {
        uint256 _endTimestamp = getEpochStart();
        uint256 reward = 0;

        for (uint256 i = tokens.length; i != 0;) {
            unchecked {
                --i;
            }
            address _rewardToken = tokens[i];
            reward = earned(account, _rewardToken);
            if (reward > 0) {
                _reserves[_rewardToken] -= reward;
                IERC20(_rewardToken).safeTransfer(account, reward);
                emit RewardPaid(account, _rewardToken, reward);
            }
            //claimed till current epoch as bribe are claimed for latest 50 epochs (t minus 50)
            userTimestamp[account][_rewardToken] = _endTimestamp;
        }
    }

    /* ========== FUNCTIONS ========== */

    function notifyRewardAmount(address _rewardsToken, uint256 reward) external nonReentrant {
        require(isRewardToken[_rewardsToken], "reward token not verified");
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), reward);
        _addBribeForEpoch(0, _rewardsToken, reward);
    }

    /**
     * @notice Notifies the contract of credited rewards from a source chain.
     * @dev Rewards can only be credited by the main chain gauge to the pool gauge deployed on the satellite chain.
     * 200000K gas limit on OFT token transfers.
     * @param srcChainId Source chain ID.
     * @param initiator Address of the bribe contract on the source chain.
     *
     * @param token Address of the reward token.
     * @param reward Amount of rewards to be credited.
     */
    function notifyCredit(uint16 srcChainId, address initiator, address, address token, uint256 reward)
        external
        nonReentrant
    {
        // Recieve bribe only on the main chain from the pool chain
        require(isMainChain && (srcChainId == lzPoolChainId), "!mainChain");

        require(msg.sender == address(ustb) && isRewardToken[token], "!reward token");

        address remoteAddress = IBribeFactory(bribeFactory).getTrustedRemoteAddress(srcChainId, address(this));

        require(initiator == remoteAddress, "not remote caller");

        nonce += 1;

        rewardCredited[nonce] = reward;
        emit RewardCredited(nonce, reward);
    }

    /**
     * @notice Acknowledges the reward credited from the main chain.
     * @dev Rewards can only be credited by the main chain gauge to the pool gauge deployed on the satellite chain.
     * @param _nonce nonce for the reward
     */
    function ackReward(uint64 _nonce) external nonReentrant {
        uint256 _reward = rewardCredited[_nonce];
        require(_reward > 0, "!reward");

        rewardCredited[_nonce] = 0;

        //update the epoch reward
        _addBribeForEpoch(_nonce, ustb, _reward);
    }

    function skim(address _to) external returns (uint256[] memory _amounts) {
        uint256 _numTokens = rewardTokens.length;
        _amounts = new uint256[](_numTokens);
        for (uint256 i = _numTokens; i != 0;) {
            unchecked {
                --i;
            }
            address _rewardToken = rewardTokens[i];
            uint256 _reserve = _reserves[_rewardToken];
            uint256 _balance = IERC20(_rewardToken).balanceOf(address(this));
            if (_balance > _reserve) {
                uint256 _amount;
                unchecked {
                    _amount = _balance - _reserve;
                }
                _amounts[i] = _amount;
                IERC20(_rewardToken).safeTransfer(_to, _amount);
            }
        }
    }

    function skim(address _rewardsToken, address _to) external returns (uint256 _amount) {
        uint256 _reserve = _reserves[_rewardsToken];
        uint256 _balance = IERC20(_rewardsToken).balanceOf(address(this));
        if (_balance > _reserve) {
            unchecked {
                _amount = _balance - _reserve;
            }
            IERC20(_rewardsToken).safeTransfer(_to, _amount);
        }
    }

    /**
     * @notice Converts a specific reward token to USTB.
     * @dev To avoid misuse, convert data is
     * compared with passed parameters to avoid exploits.
     * Only callable by keeper.
     * @param _token Token to convert.
     * @param _amount Amount to convert.
     * @param _target Target address for conversion.
     * @param _data Call data for conversion.
     */
    function convertBribeToken(address _token, uint256 _amount, address _target, bytes calldata _data)
        external
        onlyKeeper
    {
        require(!isMainChain, "mainchain");
        require(isRewardToken[_token], "invalid reward token");
        uint256 _before = IERC20(_token).balanceOf(address(this));
        uint256 _swapAmount = _amount == 0 ? _before : _amount;
        require(_before >= _swapAmount, "balance too low");
        uint256 _amountOut;
        if (_token != ustb) {
            _amountOut = _convertToken(_token, ustb, _swapAmount, _target, _data);
            require(_amountOut != 0, "insufficient output amount");
            uint256 _after = IERC20(_token).balanceOf(address(this));
            require(_after == _before - _swapAmount, "invalid input amount");
        } else {
            _amountOut = _swapAmount;
        }
        emit TokenConverted(_token, _swapAmount, _amountOut);
    }

    /**
     * @notice Transfers USTB (cross-chain US T-BILL) to the trusted main chain.
     * @dev The transfer is initiated by the keeper and send to USTB to the
     * trusted destination on the main chain.
     */
    function transferUSTB() external payable onlyKeeper {
        require(!isMainChain, "mainchain");
        uint256 balance = IOFT(ustb).balanceOf(address(this));
        if (balance > 0) {
            uint16 _dstChainId = lzMainChainId;
            address dstAddress = IBribeFactory(bribeFactory).getTrustedRemoteAddress(uint16(_dstChainId), address(this));

            IOFT(ustb).sendFrom{value: msg.value}(
                address(this),
                uint16(_dstChainId),
                abi.encodePacked(dstAddress),
                balance,
                payable(msg.sender),
                address(0),
                bytes("")
            );
        }
    }

    /// @notice Recover some ERC20 from the contract and updated given bribe
    function recoverERC20AndUpdateData(address tokenAddress, uint256 tokenAmount) external onlyRole {
        require(tokenAmount <= IERC20(tokenAddress).balanceOf(address(this)));

        uint256 _startTimestamp = IMinter(minter).active_period() + EPOCH_DURATION;
        uint256 _lastReward = _rewardData[tokenAddress][_startTimestamp].rewardsPerEpoch;
        _rewardData[tokenAddress][_startTimestamp].rewardsPerEpoch = _lastReward - tokenAmount;
        _rewardData[tokenAddress][_startTimestamp].lastUpdateTime = block.timestamp;

        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @notice Recover some ERC20 from the contract.
    /// @dev    Be careful --> if called then getReward() at last epoch will fail because some reward are missing!
    ///         Think about calling recoverERC20AndUpdateData()
    function emergencyRecoverERC20(address tokenAddress, uint256 tokenAmount) external onlyRole {
        require(tokenAmount <= IERC20(tokenAddress).balanceOf(address(this)));
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice add rewards tokens
    function addRewards(address[] memory _rewardsToken) public onlyRole {
        for (uint256 i = _rewardsToken.length; i != 0;) {
            unchecked {
                --i;
            }
            _addReward(_rewardsToken[i]);
        }
    }

    /// @notice add a single reward token
    function addReward(address _rewardsToken) public onlyRole {
        _addReward(_rewardsToken);
    }

    function _addReward(address _rewardsToken) internal {
        if (!isRewardToken[_rewardsToken]) {
            isRewardToken[_rewardsToken] = true;
            rewardTokens.push(_rewardsToken);
        }
    }

    function setVoter(address _Voter) external onlyOwner {
        require(_Voter != address(0));
        voter = _Voter;
    }

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0));
        minter = _minter;
    }

    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0));
        owner = _owner;
    }

    /* ========== VIEWS ========== */

    function getEpochStart() public view returns (uint256) {
        return IMinter(minter).active_period();
    }

    function getNextEpochStart() public view returns (uint256) {
        return getEpochStart() + EPOCH_DURATION;
    }

    function rewardData(address _token, uint256 _timestamp) external view override returns (Reward memory) {
        return _rewardData[_token][_timestamp];
    }

    function rewardsListLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply[getNextEpochStart()];
    }

    function totalSupplyAt(uint256 _timestamp) external view returns (uint256) {
        return _totalSupply[_timestamp];
    }

    function balanceOfAt(address account, uint256 _timestamp) public view returns (uint256) {
        return _balances[account][_timestamp];
    }

    // get last deposit available balance (getNextEpochStart)
    function balanceOf(address account) public view returns (uint256) {
        uint256 _timestamp = getNextEpochStart();
        return _balances[account][_timestamp];
    }

    function earned(address account, address _rewardToken) public view returns (uint256) {
        uint256 reward = 0;
        uint256 _currentTimestamp = getNextEpochStart();
        uint256 _firstBribeTimestamp = firstBribeTimestamp;
        uint256 _userLastTime = userTimestamp[account][_rewardToken];

        if (_currentTimestamp == _userLastTime) {
            return 0;
        }

        for (uint8 limit = 50; limit > 0; --limit) {
            _currentTimestamp -= EPOCH_DURATION;
            if (_userLastTime == _currentTimestamp || _firstBribeTimestamp > _currentTimestamp) {
                // if we reach the user's last claim epoch, exit
                break;
            }
            reward += _earned(account, _rewardToken, _currentTimestamp);
        }
        return reward;
    }

    function rewardPerToken(address _rewardsToken, uint256 _timestamp) public view returns (uint256) {
        uint256 _rewardsPerEpoch = _rewardData[_rewardsToken][_timestamp].rewardsPerEpoch;
        if (_totalSupply[_timestamp] == 0) {
            return _rewardsPerEpoch;
        }

        return _rewardsPerEpoch.mulDiv(PRECISION, _totalSupply[_timestamp]);
    }

    function getReward(address account, address[] calldata tokens) external nonReentrant isAllowed {
        _getReward(account, tokens);
    }

    function getRewardForOwner(address account, address[] calldata tokens) public nonReentrant isAllowed {
        require(msg.sender == voter);
        _getReward(account, tokens);
    }
}
