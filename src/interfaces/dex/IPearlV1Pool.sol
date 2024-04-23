// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title IPearlV1Pool
 * @notice Interface for Pearl V1 Pool contract.
 * @dev This interface defines functions and events for interacting with a Pearl V1 Pool contract.
 */
interface IPearlV1Pool {
    // ERC20 events

    /**
     * @dev Emitted when an approval occurs, indicating that one address approves another to spend a certain amount of tokens on its behalf.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Emitted when a transfer occurs, indicating that tokens have been transferred from one address to another.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    // ERC20 functions

    /**
     * @dev Returns the name of the token.
     * @return The name of the token as a string.
     */
    function name() external pure returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     * @return The symbol of the token as a string.
     */
    function symbol() external pure returns (string memory);

    /**
     * @dev Returns the number of decimals used to represent the token.
     * @return The number of decimals as a uint8.
     */
    function decimals() external pure returns (uint8);

    /**
     * @dev Returns the total supply of the token.
     * @return The total supply of the token as a uint.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the balance of a specified address.
     * @param owner The address to query the balance of.
     * @return The balance of the specified address as a uint.
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev Returns the amount of tokens that an owner has allowed a spender to spend on its behalf.
     * @param owner The address that owns the tokens.
     * @param spender The address that is approved to spend the tokens.
     * @return The allowance as a uint.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Approves another address to spend tokens on behalf of the caller.
     * @param spender The address to be approved for spending the tokens.
     * @param value The amount of tokens to be approved.
     * @return A boolean indicating whether the approval was successful or not.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Transfers tokens from the caller's address to the specified recipient.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return A boolean indicating whether the transfer was successful or not.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Transfers tokens from one address to another.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return A boolean indicating whether the transfer was successful or not.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    // Permit function

    /**
     * @dev Returns the domain separator hash used in the permit function.
     * @return The domain separator hash as a bytes32.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @dev Returns the type hash of the permit function.
     * @return The type hash of the permit function as a bytes32.
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    /**
     * @dev Returns the nonce for a given address used in the permit function.
     * @param owner The address for which to retrieve the nonce.
     * @return The nonce as a uint.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Allows an owner to approve a spender to spend a specified amount of tokens on its behalf using a signature.
     * @param owner The owner of the tokens.
     * @param spender The spender to be approved.
     * @param value The amount of tokens to be approved.
     * @param deadline The deadline by which the permit must be executed.
     * @param v The recovery byte of the signature.
     * @param r The R part of the signature.
     * @param s The S part of the signature.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    // Mint, burn, swap, and sync events

    /**
     * @dev Emitted when liquidity tokens are minted.
     */
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);

    /**
     * @dev Emitted when liquidity tokens are burned.
     */
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    /**
     * @dev Emitted when tokens are swapped.
     */
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /**
     * @dev Emitted when the reserves are synchronized.
     */
    event Sync(uint112 reserve0, uint112 reserve1);

    // Constants

    /**
     * @dev Returns the minimum liquidity required for a pool to exist.
     * @return The minimum liquidity as a uint.
     */
    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    /**
     * @dev Returns the address of the factory that created the pool.
     * @return The address of the factory as an address.
     */
    function factory() external view returns (address);

    /**
     * @dev Returns the address of token0.
     * @return The address of token0 as an address.
     */
    function token0() external view returns (address);

    /**
     * @dev Returns the address of token1.
     * @return The address of token1 as an address.
     */
    function token1() external view returns (address);

    // Getters for reserves, prices, and kLast

    /**
     * @dev Returns the reserves of token0 and token1 in the pool, and the block timestamp of the last interaction with the pool.
     * @return reserve0 reserves of token0
     * @return reserve1 reserves of token1
     * @return blockTimestampLast the block timestamp of latest revserve sync
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /**
     * @dev Returns the cumulative price of token0 relative to token1 since the last liquidity event.
     * @return The cumulative price of token0 relative to token1 as a uint.
     */
    function price0CumulativeLast() external view returns (uint256);

    /**
     * @dev Returns the cumulative price of token1 relative to token0 since the last liquidity event.
     * @return The cumulative price of token1 relative to token0 as a uint.
     */
    function price1CumulativeLast() external view returns (uint256);

    /**
     * @dev Returns the value of k during the last interaction with the pool.
     * @return The value of k as a uint.
     */
    function kLast() external view returns (uint256);

    // Core functions

    /**
     * @dev Mints liquidity tokens and assigns them to a recipient.
     * @param to The address to which liquidity tokens will be assigned.
     * @return liquidity amount of liquidity tokens minted as a uint.
     */
    function mint(address to) external returns (uint256 liquidity);

    /**
     * @dev Burns liquidity tokens and retrieves the underlying tokens.
     * @param to The address to which the underlying tokens will be sent.
     * @return amount0 amounts of token0
     * @return amount1 amounts of token1
     */
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /**
     * @dev Swaps tokens.
     * @param amount0Out The amount of token0 to receive.
     * @param amount1Out The amount of token1 to receive.
     * @param to The address to which the received tokens will be sent.
     * @param data Additional data to pass to the recipient.
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    /**
     * @dev Skims excess tokens from the pool and sends them to a recipient.
     * @param to The address to which the excess tokens will be sent.
     */
    function skim(address to) external;

    /**
     * @dev Synchronizes the reserves of the pool to the current balances.
     */
    function sync() external;

    // Initialization function

    /**
     * @dev Initializes the pool with the given tokens.
     * @param tokenA The address of token0.
     * @param tokenB The address of token1.
     */
    function initialize(address tokenA, address tokenB) external;
}
