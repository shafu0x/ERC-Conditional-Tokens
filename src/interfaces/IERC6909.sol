// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IERC6909 - Minimal Multi-Token Interface
/// @notice A minimal specification for managing multiple tokens by the same contract
/// @dev See https://eips.ethereum.org/EIPS/eip-6909
interface IERC6909 {
    /// @notice Emitted when `amount` tokens of id `id` are transferred from `sender` to `receiver`
    /// @param sender The address of the sender
    /// @param receiver The address of the receiver
    /// @param id The id of the token
    /// @param amount The amount of the token
    event Transfer(address indexed sender, address indexed receiver, uint256 indexed id, uint256 amount);

    /// @notice Emitted when the `owner` enables or disables `spender` as an operator
    /// @param owner The address of the owner
    /// @param spender The address of the spender
    /// @param approved The approval status
    event OperatorSet(address indexed owner, address indexed spender, bool approved);

    /// @notice Emitted when the allowance of `spender` for `owner` is set for token id `id`
    /// @param owner The address of the owner
    /// @param spender The address of the spender
    /// @param id The id of the token
    /// @param amount The new allowance amount
    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);

    /// @notice Returns the total supply of a token
    /// @param id The id of the token
    /// @return The total supply of the token
    function totalSupply(uint256 id) external view returns (uint256);

    /// @notice Returns the balance of a token
    /// @param owner The address of the owner
    /// @param id The id of the token
    /// @return The balance of the token
    function balanceOf(address owner, uint256 id) external view returns (uint256);

    /// @notice Returns the allowance of a spender for a token
    /// @param owner The address of the owner
    /// @param spender The address of the spender
    /// @param id The id of the token
    /// @return The allowance of the spender
    function allowance(address owner, address spender, uint256 id) external view returns (uint256);

    /// @notice Checks if a spender is approved by an owner as an operator
    /// @param owner The address of the owner
    /// @param spender The address of the spender
    /// @return The operator status
    function isOperator(address owner, address spender) external view returns (bool);

    /// @notice Transfers an amount of a token from the caller to a receiver
    /// @param receiver The address of the receiver
    /// @param id The id of the token
    /// @param amount The amount of the token
    /// @return success True if the transfer succeeded
    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool success);

    /// @notice Transfers an amount of a token from a sender to a receiver
    /// @param sender The address of the sender
    /// @param receiver The address of the receiver
    /// @param id The id of the token
    /// @param amount The amount of the token
    /// @return success True if the transfer succeeded
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external returns (bool success);

    /// @notice Approves an amount of a token to a spender
    /// @param spender The address of the spender
    /// @param id The id of the token
    /// @param amount The amount of the token
    /// @return success True if the approval succeeded
    function approve(address spender, uint256 id, uint256 amount) external returns (bool success);

    /// @notice Sets or removes a spender as an operator for the caller
    /// @param spender The address of the spender
    /// @param approved The operator status
    /// @return success True if the operation succeeded
    function setOperator(address spender, bool approved) external returns (bool success);
}
