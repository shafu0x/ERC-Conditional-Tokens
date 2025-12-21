---
eip: 9999
title: Conditional Tokens
description: An interface for tokens representing positions on outcomes that can be split, merged and redeemed based on oracle reported results
author: shafu (@shafu0x)
status: Draft
type: Standards Track
category: ERC
created: 2025-12-16
requires: 6909
---

## Abstract

This ERC extends ERC-6909 with conditional tokens that allow participants to create and settle positions on future outcomes.

It introduces three core operations. Splitting collateral into outcome positions, merging positions back into collateral and redeeming positions after oracle resolution.

## Motivation

Prediction markets have demonstrated product market fit through platform like Polymarket. The Gnosis Conditional Tokens framework from 2019 pioneered the core primitives of splitting, merging and redemeeing positions based on oracle outcomes. But there is no formal ERC standard, limiting interoperability.

To enable a thriving ecosystem of prediction markets and futarchy governance we need a standard interface. This ERC addresses this through three core operations:

1. **Condition Preparation**: Registers a condition with an oracle, question identifier and outcome count.
2. **Position Splitting & Merging**: Converts collateral into outcome tokens (split) or recombines them (merge).
3. **Redemptions**: Token holders can claim collateral proportional to the reported payout weights after oracle resolution.

This ERC formalizes patterns that the prediction market industry has battle-tested for years now. Providing one interface will accelerate adoption accross chains and applications.

## Adoption and Usage

- [Polymarket](https://docs.polymarket.com/developers/CTF/overview): Prediction markets using CTF on Polygon
- [Seer](https://seer.pm): Prediction and [futarchy](https://seer-3.gitbook.io/seer-documentation/developers/interact-with-seer/futarchy-market) markets using CTF (Gnosis and Ethereum)
- [Forkast](https://docs.forkast.gg/conditional-tokens-framework): Sports/gaming prediction markets using CTF-style conditional tokens (Arbitrum)
- [Omen](https://omen.eth.link): Early CTF + Reality.eth prediction markets (legacy frontend; onchain markets persist)
- [Predict Fun](https://defillama.com/protocol/predict-fun): Prediction markets using conditional token contracts (BNB Chain and Blast)
- [OPINION](https://defillama.com/protocol/opinion): Prediction exchange using a CTF-derived conditional tokens design (BNB Chain)

## Specification

### Methods

#### prepareCondition

Initialize a new condition with a fixed number of outcomes. The function generates a `conditionId` which is the `keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))` and initializes a payout vector associated to the `conditionId`

##### Parameters

- `oracle`: Account used to resolve a condition by reporting its result by calling `reportPayouts`. The `conditionId` is binded to the oracle address, so only the oracle can resolve the condition,
- `questionId`: Identifier for the question to be answered by `oracle`
- `outcomeSlotCount`: Number of outcomes for a condition. **MUST BE** `> 1` and `<= 256`

```js
function prepareCondition(address oracle, bytes32 questionId, uint outcomeSlotCount) external
```

#### reportPayouts

Oracle resolves a condition by calling this function and reports payouts for each outcome

##### Parameters

- `questionId`: Identifier for the question to be answered by `oracle`
- `payouts`: Oracle reported integer weights per outcome slot. The payout fraction for outcome slot `i` is `payoutNumerators[i] / payoutDenominator`

**NOTE**:
`msg.sender` is enforced as the oracle, because conditionId is derived from `(msg.sender, questionId, payouts.length)`.

```js
function reportPayouts(bytes32 questionId, uint[] calldata payouts) external
```

#### splitPosition

Convert one `parent` stake into multiple `child` outcome positions, either by collateral by transferring `amount` collateral from the message sender to itself or by burning `amount` stake held by the message sender in the position being split worth of EIP 1155 tokens.

##### Parameters

- `collateralToken`: The address of the position's backing collateral token
- `parentCollectionId`: Either `bytes(0)` signifying the position is backed by collateral or identifier of the parent collentionId (for nested positions)
- `conditionId`: Condition being split on.
- `partition`: Array of disjoint index sets defining non trivial partition of the outcome slots.
  E.g. `A = 0b01` and `B = 0b10`, A valid full partition array of [A, B] would mean:
  1. Its non trivial since `length > 1`
  2. Disjoint since `A & B = 0`
  3. Covers all outcomes since `A | B = 0b11`
- `amount`: Amount of collateral (if `parentCollectionId == bytes(0)`) or parent position tokens to convert into the partitioned positions

**NOTE**
A `parent` outcome collection represents a position already conditioned on prior outcomes, while a `child` outcome collection represents an additional condition on top of it.
E.g. Assume to condition statements C1 and C2 where C1 is the parent condition of C2 where:

1.  C1 is “ETH > $3k?”
2.  C2 is “ETH > $4k?”

The outcomes of `C1` are prior outcomes for `C2`, because `C2` is only evaluated within the branch where `C1` is valid.

```js
function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external
```

#### mergePositions

The inverse of `splitPosition`: burn multiple child positions to recreate a parent position or get back collateral.

##### Parameters

- `collateralToken`: The address of the position's backing collateral token
- `parentCollectionId`: Either `bytes(0)` signifying the position is backed by collateral or identifier of the parent collentionId (for nested positions)
- `conditionId`: Condition being split on.
- `partition`: Array of disjoint index sets defining non trivial partition of the outcome slots.
- `amount`: Burns amount of each child position defined by partition

**NOTE**
If partition covers fullIndexSet either collateral is sent back to the caller (if `parentCollectionId == bytes(0)`) or mints `amount` of the parent position token
If partition covers only a subset, mints `amount` of the merged subset position token.

```js
function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external
```

#### redeemPositions

After a condition is resolved, redeem outcome position tokens for their payout share.

##### Parameters

- `collateralToken`: The address of the position's backing collateral token
- `parentCollectionId`: Either `bytes(0)` for direct redemption for collateral or identifier of the parent collentionId for nested redemption
- `conditionId`: resolved condition
- `indexSets`: List of outcome collections (bitmasks) whose positions the caller wants to redeem.

**FLOW**
for each `IndexSet`, computes the caller’s balance of the corresponding `positionId`, burns it, and adds `payout += stake * payoutNumerator(indexSet) / payoutDenominator` and then transfers collateral payout to caller if (`parentCollectionId == bytes(0)`) or mints parent position if nested.

```js
function redeemPositions(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint[] calldata indexSets) external
```

#### getOutcomeSlotCount

Returns outcome slot count of a `conditionId`

##### Parameters

- `conditionId`: ID of the condition

```js
function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint)
```

#### getConditionId

Returns generated `conditionId` which is the `keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))`

##### Parameters

- `oracle`: The account assigned to report the result for the prepared condition
- `questionId`: An identifier for the question to be answered by the oracle
- `oracle`: The number of outcome slots which should be used for this condition. Must not exceed 256

```js
function getConditionId(address oracle, bytes32 questionId, uint outcomeSlotCount) external pure returns (bytes32)
```

#### getCollectionId

Returns `collectionId` constructed by a parent collection and an outcome collection.

##### Parameters

- `parentCollectionId`: Collection ID of the parent outcome collection, or bytes32(0) if there's no parent
- `conditionId`: Condition ID of the outcome collection to combine with the parent outcome collection
- `indexSet`: Index set of the outcome collection to combine with the parent outcome collection

```js
function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint indexSet) external view returns (bytes32)
```

#### getPositionId

Returns positionID from collateral token and outcome collection associated to the position

##### Parameters

- `collateralToken`: Collateral token which backs the position
- `collectionId`: ID of the outcome collection associated with this position

```js
function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint)
```

### Events

#### ConditionPreparation

Emitted when a new condition is initialized

```js
event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount
    )
```

#### ConditionResolution

Emitted when oracle executes `reportPayouts` with payouts for a certain `questionId`

```js
event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount,
        uint[] payoutNumerators
    )
```

#### PositionSplit

Emitted when a user splits collateral or position into multiple outcome positions

```js
event PositionSplit(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint[] partition,
        uint amount
    )
```

#### PositionsMerge

Emitted when a user merges multiple positions back into a parent position or collateral

```js
event PositionsMerge(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint[] partition,
        uint amount
    )
```

#### PayoutRedemption

Emitted when a user redeems positions after resolution

```js
event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint[] indexSets,
        uint payout
    )
```
