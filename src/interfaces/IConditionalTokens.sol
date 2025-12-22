// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IConditionalTokens - Interface for Conditional Tokens
/// @notice Interface for tokens representing positions on outcomes that can be split, merged and redeemed
/// @dev Extends ERC-6909 for multi-token functionality
interface IConditionalTokens {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new condition is prepared
    /// @param conditionId The unique identifier for the condition
    /// @param oracle The address authorized to report payouts for this condition
    /// @param questionId The identifier of the question being resolved
    /// @param outcomeSlotCount The number of possible outcomes (2-256)
    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount
    );

    /// @notice Emitted when an oracle resolves a condition by reporting payouts
    /// @param conditionId The resolved condition's identifier
    /// @param oracle The oracle that reported (same as msg.sender)
    /// @param questionId The question being answered
    /// @param outcomeSlotCount Number of outcomes for this condition
    /// @param payoutNumerators The payout weights for each outcome slot
    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    /// @notice Emitted when a position is split into outcome positions
    /// @param stakeholder The address performing the split
    /// @param collateralToken The ERC-20 token backing the positions
    /// @param parentCollectionId Parent collection (bytes32(0) if splitting collateral)
    /// @param conditionId The condition being split on
    /// @param partition Array of disjoint index sets defining the partition
    /// @param amount Amount of collateral/stake being split
    event PositionSplit(
        address indexed stakeholder,
        address collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    /// @notice Emitted when positions are merged back
    /// @param stakeholder The address performing the merge
    /// @param collateralToken The ERC-20 token backing the positions
    /// @param parentCollectionId Parent collection (bytes32(0) if merging to collateral)
    /// @param conditionId The condition the positions belong to
    /// @param partition Array of disjoint index sets being merged
    /// @param amount Amount of each position being merged
    event PositionsMerge(
        address indexed stakeholder,
        address collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    /// @notice Emitted when positions are redeemed after condition resolution
    /// @param redeemer The address redeeming positions
    /// @param collateralToken The ERC-20 token being redeemed
    /// @param parentCollectionId Parent collection (bytes32(0) for direct redemption)
    /// @param conditionId The resolved condition
    /// @param indexSets The outcome collections being redeemed
    /// @param payout The total payout received
    event PayoutRedemption(
        address indexed redeemer,
        address indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );

    /*//////////////////////////////////////////////////////////////
                            CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Prepares a condition with an oracle, question, and outcome count
    /// @dev Creates a conditionId = keccak256(oracle, questionId, outcomeSlotCount)
    /// @param oracle The address authorized to resolve this condition
    /// @param questionId Unique identifier for the question
    /// @param outcomeSlotCount Number of possible outcomes (must be >1 and <=256)
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external;

    /// @notice Oracle reports payout weights for each outcome
    /// @dev msg.sender is enforced as oracle via conditionId derivation
    /// @param questionId The question being resolved
    /// @param payouts Array of payout weights (sum must be >0)
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external;

    /// @notice Splits collateral or a parent position into outcome positions
    /// @param collateralToken The ERC-20 token backing the positions
    /// @param parentCollectionId bytes32(0) for collateral, else parent collection ID
    /// @param conditionId The condition to split on
    /// @param partition Array of disjoint index sets (bitmasks) defining partition
    /// @param amount Amount of collateral/stake to split
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /// @notice Merges outcome positions back into parent position or collateral
    /// @param collateralToken The ERC-20 token backing the positions
    /// @param parentCollectionId bytes32(0) for collateral return, else parent collection
    /// @param conditionId The condition the positions belong to
    /// @param partition Array of disjoint index sets to merge
    /// @param amount Amount of each position to merge
    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /// @notice Redeems positions after condition resolution
    /// @param collateralToken The ERC-20 token to receive
    /// @param parentCollectionId bytes32(0) for direct redemption, else nested
    /// @param conditionId The resolved condition
    /// @param indexSets Array of outcome collections (bitmasks) to redeem
    function redeemPositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the outcome slot count for a condition
    /// @param conditionId The condition identifier
    /// @return The number of outcome slots, or 0 if not prepared
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256);

    /// @notice Computes a condition ID from its components
    /// @param oracle The oracle address
    /// @param questionId The question identifier
    /// @param outcomeSlotCount Number of outcomes
    /// @return The keccak256 hash of the packed parameters
    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external pure returns (bytes32);

    /// @notice Computes a collection ID from parent and outcome collection
    /// @param parentCollectionId Parent collection (bytes32(0) if none)
    /// @param conditionId The condition for the outcome collection
    /// @param indexSet Bitmask of outcomes in this collection
    /// @return The collection identifier
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet) external pure returns (bytes32);

    /// @notice Computes a position ID from collateral and collection
    /// @param collateralToken The ERC-20 collateral token
    /// @param collectionId The outcome collection ID
    /// @return The position ID (used as ERC-6909 token ID)
    function getPositionId(address collateralToken, bytes32 collectionId) external pure returns (uint256);
}
