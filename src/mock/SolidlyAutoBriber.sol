// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IBribe} from "../interfaces/IBribe.sol";
import {IPearlV2Pool} from "../interfaces/dex/IPearlV2Pool.sol";
import {IPearlV2Factory} from "../interfaces/dex/IPearlV2Factory.sol";
import {IVoter} from "../interfaces/IVoter.sol";
error NotRegistered(address pair);

/**
 * @title SolidlyAutoBriber
 * @author Caesar LaVey
 * @notice This contract automates the process of distributing bribes to voting gauges in the Solidly ecosystem. It
 * subscribes to rebase events from the USTBRebaseManager contract, skims liquidity pools to collect tokens, adjusts the
 * amounts based on pseudo-transient statistics, and then deposits these tokens as bribes.
 *
 * @dev The contract inherits from `RebaseSubscriber`, `OwnableUpgradeable`, and `ReentrancyGuardUpgradeable`. It
 * utilizes the OpenZeppelin library for secure contract upgrades and reentrancy protection. The contract has a focus on
 * gas efficiency and follows the Checks-Effects-Interactions pattern.
 *
 * Key Features:
 * - Subscribes to rebase events to trigger the bribe depositing mechanism.
 * - Manages a list of liquidity pairs and corresponding voters.
 * - Skims pools to collect tokens and adjusts the skimmed amounts.
 * - Deposits the skimmed tokens as bribes to voting gauges.
 *
 * Important Points:
 * - The contract owner can register or unregister liquidity pairs.
 * - The skimmed amounts are adjusted to account for any leftover balances from previous rebases.
 * - Uses inline assembly for gas-efficient storage access.
 */
contract SolidlyAutoBriber is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct SolidlyPair {
        address pair;
        address token0;
        address token1;
        address voter;
        uint256 index;
    }

    struct TokenAmounts {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint256 balance0;
        uint256 balance1;
    }

    mapping(address => uint256) private _pairLookup;
    mapping(address => uint256) private _skimmed; // "transient" statistics for skimmed token amounts
    mapping(address => bool) private _filteredToken;

    SolidlyPair[] public allPairs;

    event AutoBribed(address indexed token, uint256 amount);
    event PairRegistered(address indexed pair);
    event PairUnregistered(address indexed pair);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract's reentrancy guard.
     * @dev This function acts as the initializer in the upgradeable contract pattern, ensuring the reentrancy guard is
     * set up. It can only be called once due to the `initializer` modifier.
     */
    function initialize(
        address[] memory filteredTokens
    ) external reinitializer(2) {
        __Ownable_init();
        __ReentrancyGuard_init();
        for (uint256 i = filteredTokens.length; i != 0; ) {
            unchecked {
                --i;
            }
            _filteredToken[filteredTokens[i]] = true;
        }
    }

    function filterToken(address token, bool filter) external onlyOwner {
        _filteredToken[token] = filter;
    }

    /**
     * @notice Fetches the number of registered liquidity pairs.
     * @dev This function is a simple getter for the length of the `allPairs` array, returning the number of liquidity
     * pairs registered in the contract.
     * @return length The number of registered liquidity pairs.
     */
    function allPairsLength() external view returns (uint256 length) {
        length = allPairs.length;
    }

    /**
     * @notice Executes actions upon receiving a rebase notification.
     * @dev Called externally and is expected to be triggered by the USTBRebaseManager after a rebase event. It skims
     * all registered pools, adjusts the skimmed amounts, and then deposits the bribes. The function is non-reentrant to
     * prevent reentrancy attacks.
     * @return Returns true to indicate successful execution.
     */
    function notify(address, uint256) external nonReentrant returns (bool) {
        TokenAmounts[] memory amounts = _skimAllPools();
        _adjustAmounts(amounts);
        _depositBribes(amounts);
        return true;
    }

    /**
     * @notice Skims all registered liquidity pools and captures the skimmed amounts.
     * @dev This internal function iterates through all registered pairs, skims the pools using the `skim` function of
     * IPearlV2Pool, and records the skimmed amounts. It returns an array of TokenAmounts structures detailing the skimmed
     * token amounts and balances.
     * @return amounts Array of TokenAmounts structures containing information about the skimmed tokens and their
     * balances.
     */
    function _skimAllPools() internal returns (TokenAmounts[] memory amounts) {
        uint256 numPairs = allPairs.length;
        amounts = new TokenAmounts[](numPairs);
        for (uint256 i = numPairs; i != 0; ) {
            unchecked {
                --i;
            }
            SolidlyPair storage $ = _unsafePairAccess(i);
            (address token0, address token1) = ($.token0, $.token1);

            // Capture the initial balances of token0 and token1 for this contract.
            uint256 balance0Before = IERC20(token0).balanceOf(address(this));
            uint256 balance1Before = IERC20(token1).balanceOf(address(this));

            // Perform the skim operation on the liquidity pool.
            IPearlV2Pool($.pair).skim();

            // Capture the balances of token0 and token1 for this contract after the skim operation.
            uint256 balance0After = IERC20(token0).balanceOf(address(this));
            uint256 balance1After = IERC20(token1).balanceOf(address(this));

            // Calculate the skimmed amounts by comparing the balances before and after the skim operation.
            uint256 skimmed0 = balance0After - balance0Before;
            uint256 skimmed1 = balance1After - balance1Before;

            // // Perform a sync operation to cover negative rebases.
            // IPearlV2Pool($.pair).sync();

            // Construct the TokenAmounts object for the skimmed tokens.
            amounts[i] = TokenAmounts({
                token0: token0,
                token1: token1,
                amount0: skimmed0,
                amount1: skimmed1,
                balance0: balance0After,
                balance1: balance1After
            });

            // Update the contract's "transient" statistics for skimmed token amounts.
            _skimmed[token0] += skimmed0;
            _skimmed[token1] += skimmed1;
        }
    }

    /**
     * @notice Adjusts the skimmed token amounts to account for any leftover balances.
     * @dev This internal function iterates over the TokenAmounts array and adjusts the skimmed amounts based on the
     * total skimmed and current balances. This ensures that all tokens are used for auto-bribes.
     *
     * @param amounts Array of TokenAmounts structures containing information about the skimmed tokens and their
     * balances.
     */
    function _adjustAmounts(TokenAmounts[] memory amounts) internal {
        uint256 totalSkimmed;
        for (uint256 i = amounts.length; i != 0; ) {
            unchecked {
                --i;
            }
            TokenAmounts memory $ = amounts[i];

            // Adjust the skimmed amount for token0 based on total skimmed and current balance.
            totalSkimmed = _skimmed[$.token0];
            if (totalSkimmed != 0) {
                $.amount0 = ($.amount0 * $.balance0) / totalSkimmed;
            }
            delete _skimmed[$.token0];

            // Adjust the skimmed amount for token1 based on total skimmed and current balance.
            totalSkimmed = _skimmed[$.token1];
            if (totalSkimmed != 0) {
                $.amount1 = ($.amount1 * $.balance1) / totalSkimmed;
            }
            delete _skimmed[$.token1];
        }
    }

    /**
     * @notice Deposits bribes using the adjusted skimmed token amounts.
     * @dev This internal function iterates through the TokenAmounts array, deposits bribes to the respective gauges
     * through the IVoter contract, and emits AutoBribed events. It only deposits if the amount is non-zero and the
     * gauge is valid.
     *
     * @param amounts Array of TokenAmounts structures containing information about the skimmed tokens and their
     * adjusted amounts.
     */
    function _depositBribes(TokenAmounts[] memory amounts) internal {
        for (uint256 i = amounts.length; i != 0; ) {
            unchecked {
                --i;
            }
            SolidlyPair storage pair = _unsafePairAccess(i);
            TokenAmounts memory $ = amounts[i];

            // Proceed only if there are skimmed amounts to deposit as bribes.
            if ($.amount0 != 0 || $.amount1 != 0) {
                IVoter voter = IVoter(pair.voter);
                address gauge = voter.gauges(pair.pair);

                // Validate the gauge and proceed only if it's active.
                if (gauge != address(0) && voter.isAlive(gauge)) {
                    address bribe = voter.external_bribes(gauge);
                    // Deposit bribe for token0 if the skimmed amount is non-zero.
                    if ($.amount0 != 0) {
                        IERC20($.token0).approve(bribe, $.amount0);
                        IBribe(bribe).notifyRewardAmount($.token0, $.amount0);
                        emit AutoBribed($.token0, $.amount0);
                    }

                    // Deposit bribe for token1 if the skimmed amount is non-zero.
                    if ($.amount1 != 0) {
                        IERC20($.token1).approve(bribe, $.amount1);
                        IBribe(bribe).notifyRewardAmount($.token1, $.amount1);
                        emit AutoBribed($.token1, $.amount1);
                    }
                }
            }
        }
    }

    /**
     * @notice Registers all liquidity pairs from a given factory with a specified voter.
     * @dev This function is only callable by the contract owner and iterates through all the pairs provided by the
     * IPearlV2PoolFactory interface, attempting to register each one.
     *
     * @param pairFactory Address of the factory contract that provides liquidity pairs.
     * @param voter Address of the voter contract responsible for managing votes and bribes.
     */
    function registerAllPairs(
        address pairFactory,
        address voter
    ) external onlyOwner {
        for (
            uint256 i = IPearlV2Factory(pairFactory).allPairsLength();
            i != 0;

        ) {
            unchecked {
                --i;
            }
            // Attempt to fetch and register each pair.
            try IPearlV2Factory(pairFactory).allPairs(i) returns (
                address pair
            ) {
                registerPair(pair, voter);
            } catch {}
        }
    }

    /**
     * @notice Registers a new liquidity pair or updates the voter of an existing pair.
     * @dev This function is only callable by the contract owner. If the pair already exists, only the voter is updated.
     * For a new pair, it fetches the tokens (which are immutable once set) and registers it.
     *
     * @param pair Address of the liquidity pair to register or update.
     * @param voter Address of the voter contract responsible for managing votes and bribes.
     */
    function registerPair(
        address pair,
        address voter
    ) public onlyOwner returns (bool registered) {
        (bool exists, SolidlyPair storage _pair) = _tryGetStoredPair(pair);
        if (exists) {
            // Update the voter for the existing pair. Tokens are immutable once the pair is registered.
            if (registered = _pair.voter != voter) {
                _pair.voter = voter;
            }
        } else {
            address token0;
            address token1;
            // Attempt to fetch the tokens for the new pair and register it. Tokens will be immutable once set.
            token0 = IPearlV2Pool(pair).token0();
            token1 = IPearlV2Pool(pair).token1();

            if (
                registered = (_filteredToken[token0] || _filteredToken[token1])
            ) {
                uint256 index = allPairs.length;
                SolidlyPair memory solidlyPair = SolidlyPair({
                    pair: pair,
                    token0: token0,
                    token1: token1,
                    voter: voter,
                    index: index
                });
                allPairs.push(solidlyPair);
                _pairLookup[pair] = index;
                emit PairRegistered(pair);
            }
        }
    }

    /**
     * @notice Unregisters a liquidity pair, removing it from the list of managed pairs.
     * @dev This function is only callable by the contract owner. It finds the pair based on the address, removes it
     * from the array, and adjusts the array accordingly. Throws an error if the pair is not found.
     *
     * @param pair Address of the liquidity pair to unregister.
     */
    function unregisterPair(address pair) public onlyOwner {
        (bool exists, SolidlyPair storage _pair) = _tryGetStoredPair(pair);
        if (exists) {
            // Remove the pair from the array, filling the gap with the last element to maintain order.
            uint256 index = _pair.index;
            uint256 lastIndex = allPairs.length - 1;
            if (index != lastIndex) {
                allPairs[index] = allPairs[lastIndex];
                allPairs[index].index = index;
            }
            allPairs.pop();
            emit PairUnregistered(pair);
        } else {
            // If the pair is not registered, throw a custom error.
            revert NotRegistered(pair);
        }
    }

    /**
     * @notice Attempts to find a SolidlyPair based on its address.
     * @dev This internal view function uses the `_pairLookup` mapping to find the index of a pair, then validates if
     * the found pair matches the given address.
     *
     * @param pair Address of the liquidity pair to look for.
     * @return found A boolean indicating whether the pair was found.
     * @return storedPair The stored SolidlyPair structure if found.
     */
    function _tryGetStoredPair(
        address pair
    ) private view returns (bool found, SolidlyPair storage storedPair) {
        assembly {
            storedPair.slot := 0
        }
        uint256 index = _pairLookup[pair];
        if (index < allPairs.length) {
            SolidlyPair storage _pair = _unsafePairAccess(index);
            found = _pair.pair == pair;
            if (found) {
                storedPair = _pair;
            }
        }
    }

    /**
     * @notice Retrieves a SolidlyPair based on its index in a gas-efficient manner.
     * @dev This internal pure function uses inline assembly to directly access storage, bypassing the usual Solidity
     * mechanisms. This is done for gas efficiency.
     *
     * @param index The index of the SolidlyPair in the `allPairs` array.
     * @return pair The stored SolidlyPair structure at the given index.
     */
    function _unsafePairAccess(
        uint256 index
    ) private pure returns (SolidlyPair storage pair) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, allPairs.slot)
            pair.slot := add(keccak256(0, 0x20), index)
        }
    }
}
