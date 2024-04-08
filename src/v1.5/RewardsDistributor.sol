// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IRewardsDistributor.sol";
import "../interfaces/IVotingEscrow.sol";
import "../Epoch.sol";

/**
 * @title Rewards Distributor Contract
 * @author SeaZarrgh
 * @dev Implementation of a rewards distributor that allocates rewards based on voting power.
 *      This contract handles the distribution of rewards in epochs, utilizing voting escrow
 *      tokens to determine the reward allocation for each holder.
 *
 * The contract utilizes the following OpenZeppelin libraries and contracts:
 * - IERC20 and SafeERC20 for safe ERC20 interactions.
 * - Initializable for upgradeability support.
 *
 * The contract imports the following custom interfaces and contracts:
 * - IRewardsDistributor for defining rewards distribution functionality.
 * - IVotingEscrow to interact with voting escrow tokens.
 * - Epoch for handling epoch-related calculations.
 *
 * Key functionalities include:
 * - Initializing the contract with a voting escrow address.
 * - Setting the depositor address responsible for supplying rewards.
 * - Claiming rewards for a given token ID based on its voting power.
 * - Managing ownership and depositors.
 * - Calculating claimable amounts for token IDs.
 * - Withdrawing ERC20 tokens from the contract.
 *
 * @notice The contract is designed to work with an upgradeable pattern and thus inherits
 *         from Initializable.
 */
contract RewardsDistributor is Initializable, IRewardsDistributor {
    using SafeERC20 for IERC20;

    address public owner;
    address public depositor;
    address public token;
    uint256 private _tokenReserve;

    uint256 public lastRewardEpochTimestamp;

    IVotingEscrow public ve;

    mapping(uint256 tokenId => uint256 timestamp) public lastTokenClaim;
    mapping(uint256 epochTimestamp => uint256 amount) public epochReward;

    /**
     * @dev Emitted when a user successfully claims tokens.
     * @param tokenId The unique identifier of the claimed token.
     * @param amount The amount of tokens claimed by the user.
     * @param claim_epoch The epoch at which the claim was made.
     * @param max_epoch The maximum epoch for claiming tokens.
     */
    event Claimed(uint256 indexed tokenId, uint256 amount, uint256 claim_epoch, uint256 max_epoch);

    /**
     * @dev Emitted when a user withdraws ERC20 tokens.
     * @param token The address of the ERC20 token being withdrawn.
     * @param owner The address of the user initiating the withdrawal.
     * @param amount The amount of ERC20 tokens withdrawn by the user.
     */
    event Withdraw(address indexed token, address owner, uint256 amount);

    error NoClaimableAmount();

    event OwnerSet(address indexed owner);
    event DepositorSet(address indexed depositor);

    error RewardsDistributor_NoWithdrawableAmount();
    error RewardsDistributor_CannotUpdateRewardForPastEpochs();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with a specified voting escrow address.
     * @dev Sets the token address to the locked token of the voting escrow and assigns the contract deployer as the owner.
     *      This function can only be called once, due to the initializer modifier from OpenZeppelin's upgradeable contracts library.
     * @param _votingEscrow The address of the voting escrow contract.
     */
    function initialize(address _intialOwner, address _votingEscrow) public initializer {
        require(_intialOwner != address(0), "zero addr");
        IVotingEscrow _ve = IVotingEscrow(_votingEscrow);
        token = address(_ve.lockedToken());
        ve = _ve;
        owner = _intialOwner;
    }

    /**
     * @notice Sets the depositor address responsible for supplying rewards.
     * @dev The depositor is the address authorized to notify the contract about new reward amounts.
     *      Only the current owner can set or change the depositor.
     *      This function reinforces the security by restricting reward management to a specific address.
     * @param _depositor The address to be set as the depositor.
     */
    function setDepositor(address _depositor) external {
        require(msg.sender == owner, "!owner");
        depositor = _depositor;
        emit DepositorSet(_depositor);
    }

    /**
     * @notice Transfers contract ownership to a new, non-zero address.
     * @dev Allows the current owner to transfer control of the contract to a new owner, provided the new owner's address is not the zero address.
     *      This added check prevents accidentally setting the zero address as the owner, which would result in losing control over the contract.
     *      The function plays a critical role in contract management, allowing for flexibility and safe transfer of control.
     *      The usage of this function must be handled with care to maintain the contract's integrity and avoid unintended loss of control.
     * @param _owner The address to be set as the new owner. Must not be the zero address.
     */
    function setOwner(address _owner) external {
        require(_owner != address(0), "zeroAddr");
        require(msg.sender == owner, "!owner");
        owner = _owner;
        emit OwnerSet(_owner);
    }

    /**
     * @notice Notifies the contract of a new reward amount for the current epoch, ensuring no past or duplicate updates.
     * @dev Only callable by the depositor. This function updates the reward amount for the current epoch, with checks to prevent
     *      retroactive or duplicate updates:
     *      - It prevents updating rewards for past epochs.
     *      - It ensures that the reward for the current epoch has not been already set.
     *      The function calculates the current epoch timestamp and, if valid, updates the reward amount.
     *      It also updates the `lastRewardEpochTimestamp` to reflect the most recent epoch for which rewards have been notified.
     *      These checks are crucial to maintain the integrity and correctness of the reward distribution process.
     * @param amount The amount of reward to be added for the current epoch.
     */
    function notifyRewardAmount(uint256 amount) external {
        require(msg.sender == depositor, "!depositor");
        uint256 epochTimestamp = _currentEpochTimestamp();
        uint256 _lastRewardEpochTimestamp = lastRewardEpochTimestamp;
        if (epochTimestamp < _lastRewardEpochTimestamp) {
            revert RewardsDistributor_CannotUpdateRewardForPastEpochs();
        }

        epochReward[epochTimestamp] += amount;
        _tokenReserve += amount;
        lastRewardEpochTimestamp = epochTimestamp;
    }

    /**
     * @notice Calculates the amount of rewards claimable by a specific token ID.
     * @dev This view function computes the claimable rewards for a given token ID, considering its past voting power in each epoch.
     *      It iterates through each epoch since the token's last claim or minting time, aggregating the proportional reward.
     *      The reward for each epoch is calculated based on the token's voting power relative to the total voting power at that time.
     *      This function is essential for understanding the pending rewards for any token at any point in time.
     * @param tokenId The token ID for which to calculate claimable rewards.
     * @return amount The total amount of rewards claimable by the given token ID.
     */
    function claimable(uint256 tokenId) public view returns (uint256 amount) {
        (amount,) = _claimable(tokenId);
    }

    /**
     * @notice Calculates the amount of rewards claimable by a specific token ID.
     * @param tokenId The token ID for which to calculate claimable rewards.
     * @return amount The total amount of rewards claimable by the given token ID.
     */
    function _claimable(uint256 tokenId) internal view returns (uint256 amount, uint256 lastClaimEpochTimestamp) {
        uint256 lastClaimTimestamp = lastTokenClaim[tokenId];
        if (lastClaimTimestamp == 0) {
            lastClaimTimestamp = ve.getMintingTimestamp(tokenId);
            if (lastClaimTimestamp == 0) return (0, 0);
        }
        uint256 limit = 50; // max 50 past epochs at a time
        uint256 epochTimestamp = lastRewardEpochTimestamp;
        lastClaimEpochTimestamp = _toEpochTimestamp(lastClaimTimestamp) + EPOCH_DURATION;
        while (lastClaimEpochTimestamp < epochTimestamp && (limit != 0 || amount == 0)) {
            uint256 pastVotingPower = ve.getPastVotingPower(tokenId, lastClaimEpochTimestamp);

            if (pastVotingPower != 0) {
                uint256 pastTotalVotingPower = ve.getPastTotalVotingPower(lastClaimEpochTimestamp);

                if (pastTotalVotingPower != 0) {
                    amount += (epochReward[lastClaimEpochTimestamp] * pastVotingPower) / pastTotalVotingPower;
                }
            }
            unchecked {
                lastClaimEpochTimestamp += EPOCH_DURATION;
                if (limit != 0) {
                    --limit;
                }
            }
        }
        lastClaimEpochTimestamp -= EPOCH_DURATION;
    }

    /**
     * @notice Claims the rewards for a given token ID, distributing them based on vesting status.
     * @dev This function allows a token holder to claim their accrued rewards. It calculates the claimable amount and updates the last claim timestamp.
     *      If the token is fully vested (i.e., its vesting duration is over), the rewards are directly transferred to the claimer.
     *      Otherwise, the rewards are deposited back into the voting escrow on behalf of the token ID.
     *      This mechanism aligns with the vesting logic, ensuring rewards are handled according to the vesting status of each token.
     * @param tokenId The token ID for which to claim rewards.
     * @return amount The amount of rewards claimed.
     */
    function claim(uint256 tokenId) external returns (uint256 amount) {
        uint256 lastClaimEpochTimestamp;
        (amount, lastClaimEpochTimestamp) = _claimable(tokenId);
        lastTokenClaim[tokenId] = lastClaimEpochTimestamp;

        if (amount == 0) {
            revert NoClaimableAmount();
        }

        _tokenReserve -= amount;
        if (ve.getRemainingVestingDuration(tokenId) == 0) {
            address user = ve.ownerOf(tokenId);
            ve.lockedToken().safeTransfer(user, amount);
        } else {
            ve.lockedToken().forceApprove(address(ve), amount);
            ve.depositFor(tokenId, amount);
        }

        uint256 max_epoch = _currentEpochTimestamp() - 1;
        emit Claimed(tokenId, amount, lastClaimEpochTimestamp, max_epoch);
    }

    /**
     * @notice Converts a given timestamp to the start timestamp of its corresponding epoch.
     * @dev This internal pure function is used to normalize any given timestamp to the start of the epoch it falls in.
     *      It's critical for functions that rely on epoch-based calculations, ensuring consistent epoch alignment across the contract.
     *      The function divides the provided timestamp by the epoch duration and then multiplies it back,
     *      effectively rounding down to the nearest epoch start timestamp.
     * @param _timestamp The timestamp to convert.
     * @return The start timestamp of the epoch in which the given timestamp falls.
     */
    function _toEpochTimestamp(uint256 _timestamp) internal pure returns (uint256) {
        return (_timestamp / EPOCH_DURATION) * EPOCH_DURATION;
    }

    /**
     * @notice Retrieves the start timestamp of the current epoch.
     * @dev This internal view function provides the start timestamp of the epoch that includes the current block timestamp.
     *      It is a convenience function built on top of `_toEpochTimestamp`, ensuring a consistent approach to determining the current epoch's start.
     *      This function is used in various parts of the contract where the current epoch timestamp is required for calculations or logic checks.
     * @return The start timestamp of the current epoch.
     */
    function _currentEpochTimestamp() internal view returns (uint256) {
        return _toEpochTimestamp(block.timestamp);
    }

    /**
     * @notice Withdraws ERC20 tokens from the contract, accounting for the main token's reserved balance.
     * @dev Allows the owner to withdraw any ERC20 tokens held by this contract. For the contract's main token,
     *      it only allows withdrawal of the balance exceeding the reserved amount tracked by `_tokenReserve`.
     *      This ensures that the reserved portion of the main token is not withdrawn, maintaining the integrity of the rewards mechanism.
     *      If there's no withdrawable amount for the main token, the function reverts.
     *      For other tokens, it permits withdrawal of the entire balance.
     * @param _token The address of the ERC20 token to withdraw.
     */
    function withdrawERC20(address _token) external {
        require(msg.sender == owner, "!owner");
        uint256 withdrawableAmount = IERC20(_token).balanceOf(address(this));
        if (_token == token) {
            withdrawableAmount -= _tokenReserve;
            if (withdrawableAmount == 0) {
                revert RewardsDistributor_NoWithdrawableAmount();
            }
        }
        IERC20(_token).safeTransfer(msg.sender, withdrawableAmount);
        emit Withdraw(_token, msg.sender, withdrawableAmount);
    }
}
