// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC6909} from "./ERC6909.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {CTHelpers} from "./libraries/CTHelpers.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ConditionalTokens - ERC Conditional Tokens Reference Implementation
/// @notice Tokens representing positions on outcomes that can be split, merged and redeemed
/// @dev Extends ERC-6909 for gas-efficient multi-token position management
/// @author shafu (@shafu0x)
contract ConditionalTokens is ERC6909, IConditionalTokens {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TooFewOutcomes();
    error TooManyOutcomes();
    error ConditionAlreadyPrepared();
    error ConditionNotPrepared();
    error ConditionNotResolved();
    error ConditionAlreadyResolved();
    error PayoutAllZeroes();
    error EmptyOrSingletonPartition();
    error InvalidIndexSet();
    error PartitionNotDisjoint();

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Payout numerators per condition ID
    /// @dev Array length indicates outcome slot count; empty = not prepared
    mapping(bytes32 conditionId => uint256[]) public payoutNumerators;

    /// @notice Payout denominator per condition ID
    /// @dev Non-zero = condition resolved
    mapping(bytes32 conditionId => uint256) public payoutDenominator;

    /*//////////////////////////////////////////////////////////////
                          CONDITION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IConditionalTokens
    function prepareCondition(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external {
        // Validate outcome count: must be 2-256
        if (outcomeSlotCount <= 1) revert TooFewOutcomes();
        if (outcomeSlotCount > 256) revert TooManyOutcomes();

        bytes32 conditionId = CTHelpers.getConditionId(oracle, questionId, outcomeSlotCount);

        // Prevent re-preparation
        if (payoutNumerators[conditionId].length != 0) revert ConditionAlreadyPrepared();

        // Initialize payout vector with zeros
        payoutNumerators[conditionId] = new uint256[](outcomeSlotCount);

        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    /// @inheritdoc IConditionalTokens
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external {
        uint256 outcomeSlotCount = payouts.length;
        if (outcomeSlotCount <= 1) revert TooFewOutcomes();

        // Oracle is enforced via conditionId derivation (msg.sender is the oracle)
        bytes32 conditionId = CTHelpers.getConditionId(msg.sender, questionId, outcomeSlotCount);

        // Condition must be prepared with matching outcome count
        if (payoutNumerators[conditionId].length != outcomeSlotCount) revert ConditionNotPrepared();

        // Prevent double resolution
        if (payoutDenominator[conditionId] != 0) revert ConditionAlreadyResolved();

        // Calculate denominator and set numerators
        uint256 den = 0;
        for (uint256 i = 0; i < outcomeSlotCount;) {
            uint256 num = payouts[i];
            den += num;
            payoutNumerators[conditionId][i] = num;
            unchecked { ++i; }
        }

        if (den == 0) revert PayoutAllZeroes();
        payoutDenominator[conditionId] = den;

        emit ConditionResolution(conditionId, msg.sender, questionId, outcomeSlotCount, payoutNumerators[conditionId]);
    }

    /*//////////////////////////////////////////////////////////////
                          POSITION OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IConditionalTokens
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external {
        // Validate partition has at least 2 elements
        if (partition.length <= 1) revert EmptyOrSingletonPartition();

        uint256 outcomeSlotCount = payoutNumerators[conditionId].length;
        if (outcomeSlotCount == 0) revert ConditionNotPrepared();

        // Full index set for this condition (e.g., 0b111 for 3 outcomes)
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        // Process partition and mint position tokens
        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            // Validate: indexSet must be non-empty and not cover all outcomes
            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();

            // Validate: partition must be disjoint
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();

            // Mark these outcomes as used
            freeIndexSet ^= indexSet;

            // Mint position token for this index set
            bytes32 collectionId = CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
            uint256 positionId = CTHelpers.getPositionId(collateralToken, collectionId);
            _mint(msg.sender, positionId, amount);

            unchecked { ++i; }
        }

        // Handle collateral/parent position
        if (freeIndexSet == 0) {
            // Full partition: take collateral or burn parent position
            if (parentCollectionId == bytes32(0)) {
                // Transfer collateral from sender
                IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);
            } else {
                // Burn parent position
                uint256 parentPositionId = CTHelpers.getPositionId(collateralToken, parentCollectionId);
                _burn(msg.sender, parentPositionId, amount);
            }
        } else {
            // Partial partition: burn the merged subset position
            bytes32 mergedCollectionId = CTHelpers.getCollectionId(
                parentCollectionId,
                conditionId,
                fullIndexSet ^ freeIndexSet
            );
            uint256 mergedPositionId = CTHelpers.getPositionId(collateralToken, mergedCollectionId);
            _burn(msg.sender, mergedPositionId, amount);
        }

        emit PositionSplit(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /// @inheritdoc IConditionalTokens
    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external {
        if (partition.length <= 1) revert EmptyOrSingletonPartition();

        uint256 outcomeSlotCount = payoutNumerators[conditionId].length;
        if (outcomeSlotCount == 0) revert ConditionNotPrepared();

        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        // Burn position tokens for each partition element
        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();

            freeIndexSet ^= indexSet;

            bytes32 collectionId = CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
            uint256 positionId = CTHelpers.getPositionId(collateralToken, collectionId);
            _burn(msg.sender, positionId, amount);

            unchecked { ++i; }
        }

        // Return collateral/parent position or mint merged position
        if (freeIndexSet == 0) {
            // Full partition merged
            if (parentCollectionId == bytes32(0)) {
                // Return collateral
                IERC20(collateralToken).safeTransfer(msg.sender, amount);
            } else {
                // Mint parent position
                uint256 parentPositionId = CTHelpers.getPositionId(collateralToken, parentCollectionId);
                _mint(msg.sender, parentPositionId, amount);
            }
        } else {
            // Partial merge: mint merged subset position
            bytes32 mergedCollectionId = CTHelpers.getCollectionId(
                parentCollectionId,
                conditionId,
                fullIndexSet ^ freeIndexSet
            );
            uint256 mergedPositionId = CTHelpers.getPositionId(collateralToken, mergedCollectionId);
            _mint(msg.sender, mergedPositionId, amount);
        }

        emit PositionsMerge(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /// @inheritdoc IConditionalTokens
    function redeemPositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external {
        uint256 den = payoutDenominator[conditionId];
        if (den == 0) revert ConditionNotResolved();

        uint256 outcomeSlotCount = payoutNumerators[conditionId].length;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;

        uint256 totalPayout = 0;

        for (uint256 i = 0; i < indexSets.length;) {
            uint256 indexSet = indexSets[i];

            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();

            bytes32 collectionId = CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
            uint256 positionId = CTHelpers.getPositionId(collateralToken, collectionId);

            // Calculate payout numerator for this index set
            uint256 payoutNumerator = 0;
            for (uint256 j = 0; j < outcomeSlotCount;) {
                if ((indexSet & (1 << j)) != 0) {
                    payoutNumerator += payoutNumerators[conditionId][j];
                }
                unchecked { ++j; }
            }

            // Get and burn user's balance
            uint256 payoutStake = balanceOf(msg.sender, positionId);
            if (payoutStake > 0) {
                totalPayout += (payoutStake * payoutNumerator) / den;
                _burn(msg.sender, positionId, payoutStake);
            }

            unchecked { ++i; }
        }

        // Transfer payout
        if (totalPayout > 0) {
            if (parentCollectionId == bytes32(0)) {
                // Direct redemption: transfer collateral
                IERC20(collateralToken).safeTransfer(msg.sender, totalPayout);
            } else {
                // Nested redemption: mint parent position
                uint256 parentPositionId = CTHelpers.getPositionId(collateralToken, parentCollectionId);
                _mint(msg.sender, parentPositionId, totalPayout);
            }
        }

        emit PayoutRedemption(msg.sender, collateralToken, parentCollectionId, conditionId, indexSets, totalPayout);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IConditionalTokens
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256) {
        return payoutNumerators[conditionId].length;
    }

    /// @inheritdoc IConditionalTokens
    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external pure returns (bytes32) {
        return CTHelpers.getConditionId(oracle, questionId, outcomeSlotCount);
    }

    /// @inheritdoc IConditionalTokens
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external pure returns (bytes32) {
        return CTHelpers.getCollectionId(parentCollectionId, conditionId, indexSet);
    }

    /// @inheritdoc IConditionalTokens
    function getPositionId(
        address collateralToken,
        bytes32 collectionId
    ) external pure returns (uint256) {
        return CTHelpers.getPositionId(collateralToken, collectionId);
    }
}
