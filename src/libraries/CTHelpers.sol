// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CTHelpers - Conditional Tokens Helper Library
/// @notice Pure functions for computing condition, collection, and position IDs
/// @dev All ID derivations follow the ERC Conditional Tokens specification
library CTHelpers {
    /// @notice Computes a condition ID from oracle, question, and outcome count
    /// @dev conditionId = keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))
    /// @param oracle The address authorized to resolve this condition
    /// @param questionId The unique question identifier
    /// @param outcomeSlotCount Number of possible outcomes
    /// @return The unique condition identifier
    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /// @notice Computes a collection ID from parent collection and outcome collection
    /// @dev Uses hash-based derivation for collision resistance in nested positions
    /// @param parentCollectionId The parent collection (bytes32(0) if none)
    /// @param conditionId The condition this collection belongs to
    /// @param indexSet Bitmask representing which outcomes are in this collection
    /// @return The unique collection identifier
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) internal pure returns (bytes32) {
        // Hash-based approach for collision resistance
        // XOR with parent to maintain reversibility for nested positions
        return bytes32(
            uint256(parentCollectionId) ^
            uint256(keccak256(abi.encodePacked(conditionId, indexSet)))
        );
    }

    /// @notice Computes a position ID from collateral token and collection
    /// @dev The position ID becomes the ERC-6909 token ID
    /// @param collateralToken The ERC-20 collateral backing this position
    /// @param collectionId The outcome collection for this position
    /// @return The unique position identifier (ERC-6909 token ID)
    function getPositionId(
        address collateralToken,
        bytes32 collectionId
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }
}
