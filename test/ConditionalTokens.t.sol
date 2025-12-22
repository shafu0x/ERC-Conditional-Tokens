// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {IConditionalTokens} from "../src/interfaces/IConditionalTokens.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/// @title ConditionalTokensTest - Unit Tests for ERC Conditional Tokens
/// @notice Comprehensive test coverage for prepareCondition, reportPayouts, splitPosition, mergePositions, redeemPositions
contract ConditionalTokensTest is Test {
    ConditionalTokens public ct;
    ERC20Mock public collateral;

    address public oracle = address(0xCAFE);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    bytes32 public questionId = keccak256("Will ETH be above $5000 on 2025-12-31?");

    // Common test values
    uint256 constant OUTCOME_COUNT = 2; // Binary outcome: Yes/No
    uint256 constant COLLATERAL_AMOUNT = 100 ether;

    // Index sets for binary outcomes (bitmasks)
    uint256 constant YES = 1; // 0b01 - Outcome 0
    uint256 constant NO = 2;  // 0b10 - Outcome 1

    function setUp() public {
        ct = new ConditionalTokens();
        collateral = new ERC20Mock();

        // Fund Alice
        collateral.mint(alice, 1000 ether);

        // Alice approves ConditionalTokens
        vm.prank(alice);
        collateral.approve(address(ct), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        CONDITION PREPARATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_prepareCondition_success() public {
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        vm.expectEmit(true, true, true, true);
        emit IConditionalTokens.ConditionPreparation(conditionId, oracle, questionId, OUTCOME_COUNT);

        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);

        assertEq(ct.getOutcomeSlotCount(conditionId), OUTCOME_COUNT);
    }

    function test_prepareCondition_revert_tooFewOutcomes() public {
        vm.expectRevert(ConditionalTokens.TooFewOutcomes.selector);
        ct.prepareCondition(oracle, questionId, 1);

        vm.expectRevert(ConditionalTokens.TooFewOutcomes.selector);
        ct.prepareCondition(oracle, questionId, 0);
    }

    function test_prepareCondition_revert_tooManyOutcomes() public {
        vm.expectRevert(ConditionalTokens.TooManyOutcomes.selector);
        ct.prepareCondition(oracle, questionId, 257);
    }

    function test_prepareCondition_revert_alreadyPrepared() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);

        vm.expectRevert(ConditionalTokens.ConditionAlreadyPrepared.selector);
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
    }

    function test_prepareCondition_differentOracles_canPrepare() public {
        address oracle2 = address(0xDEAD);

        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        ct.prepareCondition(oracle2, questionId, OUTCOME_COUNT);

        bytes32 conditionId1 = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId2 = ct.getConditionId(oracle2, questionId, OUTCOME_COUNT);

        assertNotEq(conditionId1, conditionId2);
        assertEq(ct.getOutcomeSlotCount(conditionId1), OUTCOME_COUNT);
        assertEq(ct.getOutcomeSlotCount(conditionId2), OUTCOME_COUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        PAYOUT REPORTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reportPayouts_success_binaryWin() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1; // YES wins
        payouts[1] = 0; // NO loses

        vm.expectEmit(true, true, true, true);
        emit IConditionalTokens.ConditionResolution(conditionId, oracle, questionId, OUTCOME_COUNT, payouts);

        vm.prank(oracle);
        ct.reportPayouts(questionId, payouts);

        assertEq(ct.payoutDenominator(conditionId), 1);
        (uint256 num0) = ct.payoutNumerators(conditionId, 0);
        (uint256 num1) = ct.payoutNumerators(conditionId, 1);
        assertEq(num0, 1);
        assertEq(num1, 0);
    }

    function test_reportPayouts_success_splitPayout() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 50; // 50% to YES
        payouts[1] = 50; // 50% to NO

        vm.prank(oracle);
        ct.reportPayouts(questionId, payouts);

        assertEq(ct.payoutDenominator(conditionId), 100);
    }

    function test_reportPayouts_revert_wrongOracle() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        // Alice tries to report but she's not the oracle
        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.ConditionNotPrepared.selector);
        ct.reportPayouts(questionId, payouts);
    }

    function test_reportPayouts_revert_notPrepared() public {
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.prank(oracle);
        vm.expectRevert(ConditionalTokens.ConditionNotPrepared.selector);
        ct.reportPayouts(questionId, payouts);
    }

    function test_reportPayouts_revert_alreadyResolved() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.prank(oracle);
        ct.reportPayouts(questionId, payouts);

        vm.prank(oracle);
        vm.expectRevert(ConditionalTokens.ConditionAlreadyResolved.selector);
        ct.reportPayouts(questionId, payouts);
    }

    function test_reportPayouts_revert_allZeroes() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 0;
        payouts[1] = 0;

        vm.prank(oracle);
        vm.expectRevert(ConditionalTokens.PayoutAllZeroes.selector);
        ct.reportPayouts(questionId, payouts);
    }

    /*//////////////////////////////////////////////////////////////
                        SPLIT POSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_splitPosition_fromCollateral() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Check collateral transferred
        assertEq(collateral.balanceOf(alice), aliceBalanceBefore - COLLATERAL_AMOUNT);
        assertEq(collateral.balanceOf(address(ct)), COLLATERAL_AMOUNT);

        // Check position tokens minted
        bytes32 yesCollectionId = ct.getCollectionId(bytes32(0), conditionId, YES);
        bytes32 noCollectionId = ct.getCollectionId(bytes32(0), conditionId, NO);
        uint256 yesPositionId = ct.getPositionId(address(collateral), yesCollectionId);
        uint256 noPositionId = ct.getPositionId(address(collateral), noCollectionId);

        assertEq(ct.balanceOf(alice, yesPositionId), COLLATERAL_AMOUNT);
        assertEq(ct.balanceOf(alice, noPositionId), COLLATERAL_AMOUNT);
    }

    function test_splitPosition_revert_emptyPartition() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory partition = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.EmptyOrSingletonPartition.selector);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);
    }

    function test_splitPosition_revert_singletonPartition() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory partition = new uint256[](1);
        partition[0] = YES;

        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.EmptyOrSingletonPartition.selector);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);
    }

    function test_splitPosition_revert_notDisjoint() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        // Try to split with overlapping sets
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // A
        partition[1] = 1; // A again (overlaps!)

        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.PartitionNotDisjoint.selector);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);
    }

    function test_splitPosition_revert_invalidIndexSet() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        // Index set 3 (0b11) is the full set for 2 outcomes - invalid as single partition element
        uint256[] memory partition = new uint256[](2);
        partition[0] = 3; // Full set - invalid
        partition[1] = 0; // Empty - invalid

        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.InvalidIndexSet.selector);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);
    }

    function test_splitPosition_revert_conditionNotPrepared() public {
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.ConditionNotPrepared.selector);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        MERGE POSITIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_mergePositions_toCollateral() public {
        // Setup: split first
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Now merge back
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        ct.mergePositions(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Check collateral returned
        assertEq(collateral.balanceOf(alice), aliceBalanceBefore + COLLATERAL_AMOUNT);

        // Check position tokens burned
        bytes32 yesCollectionId = ct.getCollectionId(bytes32(0), conditionId, YES);
        bytes32 noCollectionId = ct.getCollectionId(bytes32(0), conditionId, NO);
        uint256 yesPositionId = ct.getPositionId(address(collateral), yesCollectionId);
        uint256 noPositionId = ct.getPositionId(address(collateral), noCollectionId);

        assertEq(ct.balanceOf(alice, yesPositionId), 0);
        assertEq(ct.balanceOf(alice, noPositionId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_redeemPositions_fullPayout() public {
        // Setup
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        // Alice splits
        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Oracle resolves: YES wins 100%
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.prank(oracle);
        ct.reportPayouts(questionId, payouts);

        // Alice redeems her YES position
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = YES;

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        ct.redeemPositions(address(collateral), bytes32(0), conditionId, indexSets);

        // Should get full collateral back
        assertEq(collateral.balanceOf(alice), aliceBalanceBefore + COLLATERAL_AMOUNT);
    }

    function test_redeemPositions_losingPosition() public {
        // Setup
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        // Alice splits
        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Oracle resolves: YES wins, NO loses
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        vm.prank(oracle);
        ct.reportPayouts(questionId, payouts);

        // Alice redeems her NO position (worthless)
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = NO;

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        ct.redeemPositions(address(collateral), bytes32(0), conditionId, indexSets);

        // Should get nothing
        assertEq(collateral.balanceOf(alice), aliceBalanceBefore);
    }

    function test_redeemPositions_partialPayout() public {
        // Setup
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        // Alice splits
        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Oracle resolves: 60/40 split
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 60;
        payouts[1] = 40;

        vm.prank(oracle);
        ct.reportPayouts(questionId, payouts);

        // Alice redeems YES position
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = YES;

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        ct.redeemPositions(address(collateral), bytes32(0), conditionId, indexSets);

        // Should get 60% of collateral
        assertEq(collateral.balanceOf(alice), aliceBalanceBefore + (COLLATERAL_AMOUNT * 60 / 100));
    }

    function test_redeemPositions_revert_notResolved() public {
        ct.prepareCondition(oracle, questionId, OUTCOME_COUNT);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);

        uint256[] memory partition = new uint256[](2);
        partition[0] = YES;
        partition[1] = NO;

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Try to redeem before resolution
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = YES;

        vm.prank(alice);
        vm.expectRevert(ConditionalTokens.ConditionNotResolved.selector);
        ct.redeemPositions(address(collateral), bytes32(0), conditionId, indexSets);
    }

    /*//////////////////////////////////////////////////////////////
                        ID DERIVATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getConditionId_deterministic() public view {
        bytes32 id1 = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);
        bytes32 id2 = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);
        assertEq(id1, id2);
    }

    function test_getConditionId_matchesSpec() public view {
        bytes32 expected = keccak256(abi.encodePacked(oracle, questionId, OUTCOME_COUNT));
        bytes32 actual = ct.getConditionId(oracle, questionId, OUTCOME_COUNT);
        assertEq(actual, expected);
    }

    function test_getPositionId_uniquePerCollateral() public view {
        address usdc = address(0x1);
        address dai = address(0x2);
        bytes32 collectionId = bytes32(uint256(1));

        uint256 usdcPositionId = ct.getPositionId(usdc, collectionId);
        uint256 daiPositionId = ct.getPositionId(dai, collectionId);

        assertNotEq(usdcPositionId, daiPositionId);
    }

    /*//////////////////////////////////////////////////////////////
                        THREE OUTCOME TESTS
    //////////////////////////////////////////////////////////////*/

    function test_threeOutcome_fullPartition() public {
        uint256 threeOutcomes = 3;
        ct.prepareCondition(oracle, questionId, threeOutcomes);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, threeOutcomes);

        // Split into A, B, C
        uint256[] memory partition = new uint256[](3);
        partition[0] = 1; // A (0b001)
        partition[1] = 2; // B (0b010)
        partition[2] = 4; // C (0b100)

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, partition, COLLATERAL_AMOUNT);

        // Verify all three positions minted
        for (uint256 i = 0; i < 3; i++) {
            bytes32 collectionId = ct.getCollectionId(bytes32(0), conditionId, partition[i]);
            uint256 positionId = ct.getPositionId(address(collateral), collectionId);
            assertEq(ct.balanceOf(alice, positionId), COLLATERAL_AMOUNT);
        }
    }

    function test_threeOutcome_partialPartition() public {
        uint256 threeOutcomes = 3;
        ct.prepareCondition(oracle, questionId, threeOutcomes);
        bytes32 conditionId = ct.getConditionId(oracle, questionId, threeOutcomes);

        // First, Alice needs to get (A|B) position to split
        // Split into (A|B) and C
        uint256[] memory fullPartition = new uint256[](2);
        fullPartition[0] = 3; // A|B (0b011)
        fullPartition[1] = 4; // C (0b100)

        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, fullPartition, COLLATERAL_AMOUNT);

        // Now split (A|B) into A and B
        uint256[] memory subPartition = new uint256[](2);
        subPartition[0] = 1; // A (0b001)
        subPartition[1] = 2; // B (0b010)

        bytes32 abCollectionId = ct.getCollectionId(bytes32(0), conditionId, 3);
        uint256 abPositionId = ct.getPositionId(address(collateral), abCollectionId);

        // Alice has (A|B) tokens
        assertEq(ct.balanceOf(alice, abPositionId), COLLATERAL_AMOUNT);

        // Split from the merged position
        vm.prank(alice);
        ct.splitPosition(address(collateral), bytes32(0), conditionId, subPartition, COLLATERAL_AMOUNT);

        // Now Alice should have A, B individually (A|B burned)
        assertEq(ct.balanceOf(alice, abPositionId), 0);

        bytes32 aCollectionId = ct.getCollectionId(bytes32(0), conditionId, 1);
        bytes32 bCollectionId = ct.getCollectionId(bytes32(0), conditionId, 2);
        uint256 aPositionId = ct.getPositionId(address(collateral), aCollectionId);
        uint256 bPositionId = ct.getPositionId(address(collateral), bCollectionId);

        assertEq(ct.balanceOf(alice, aPositionId), COLLATERAL_AMOUNT);
        assertEq(ct.balanceOf(alice, bPositionId), COLLATERAL_AMOUNT);
    }
}
