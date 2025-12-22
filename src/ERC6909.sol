// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC6909} from "./interfaces/IERC6909.sol";

/// @title ERC6909 - Minimal Multi-Token Implementation
/// @notice A gas-efficient multi-token implementation per EIP-6909
/// @dev Used as the base for Conditional Tokens (position tokens are ERC-6909 IDs)
abstract contract ERC6909 is IERC6909 {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Total supply per token ID
    mapping(uint256 id => uint256) internal _totalSupply;

    /// @dev Balance per owner per token ID
    mapping(address owner => mapping(uint256 id => uint256)) internal _balanceOf;

    /// @dev Allowance per owner per spender per token ID
    mapping(address owner => mapping(address spender => mapping(uint256 id => uint256))) internal _allowance;

    /// @dev Operator status per owner per spender
    mapping(address owner => mapping(address spender => bool)) internal _isOperator;

    /*//////////////////////////////////////////////////////////////
                              ERC6909 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC6909
    function totalSupply(uint256 id) external view override returns (uint256) {
        return _totalSupply[id];
    }

    /// @inheritdoc IERC6909
    function balanceOf(address owner, uint256 id) public view override returns (uint256) {
        return _balanceOf[owner][id];
    }

    /// @inheritdoc IERC6909
    function allowance(address owner, address spender, uint256 id) public view override returns (uint256) {
        return _allowance[owner][spender][id];
    }

    /// @inheritdoc IERC6909
    function isOperator(address owner, address spender) public view override returns (bool) {
        return _isOperator[owner][spender];
    }

    /*//////////////////////////////////////////////////////////////
                            ERC6909 MUTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC6909
    function transfer(address receiver, uint256 id, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, receiver, id, amount);
        return true;
    }

    /// @inheritdoc IERC6909
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external override returns (bool) {
        if (msg.sender != sender && !_isOperator[sender][msg.sender]) {
            uint256 allowed = _allowance[sender][msg.sender][id];
            if (allowed != type(uint256).max) {
                _allowance[sender][msg.sender][id] = allowed - amount;
            }
        }
        _transfer(sender, receiver, id, amount);
        return true;
    }

    /// @inheritdoc IERC6909
    function approve(address spender, uint256 id, uint256 amount) external override returns (bool) {
        _allowance[msg.sender][spender][id] = amount;
        emit Approval(msg.sender, spender, id, amount);
        return true;
    }

    /// @inheritdoc IERC6909
    function setOperator(address spender, bool approved) external override returns (bool) {
        _isOperator[msg.sender][spender] = approved;
        emit OperatorSet(msg.sender, spender, approved);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Transfers tokens from sender to receiver
    function _transfer(address sender, address receiver, uint256 id, uint256 amount) internal {
        _balanceOf[sender][id] -= amount;
        unchecked {
            _balanceOf[receiver][id] += amount;
        }
        emit Transfer(sender, receiver, id, amount);
    }

    /// @dev Mints tokens to a receiver
    function _mint(address receiver, uint256 id, uint256 amount) internal {
        _totalSupply[id] += amount;
        unchecked {
            _balanceOf[receiver][id] += amount;
        }
        emit Transfer(address(0), receiver, id, amount);
    }

    /// @dev Burns tokens from an owner
    function _burn(address owner, uint256 id, uint256 amount) internal {
        _balanceOf[owner][id] -= amount;
        unchecked {
            _totalSupply[id] -= amount;
        }
        emit Transfer(owner, address(0), id, amount);
    }
}
