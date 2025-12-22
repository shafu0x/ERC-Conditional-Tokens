---
eip: XXX
title: Conditional Tokens
description: An interface for tokens representing positions on outcomes that can be split, merged, and redeemed based on oracle-reported results
author: shafu (@shafu0x), mihir (@0xmihirsahu)
status: Draft
type: Standards Track
category: ERC
created: 2025-12-16
requires: 6909
---

## Abstract

This ERC extends ERC-6909 with conditional tokens that allow participants to create and settle positions on future outcomes.

It introduces three core operations: splitting collateral into outcome positions, merging positions back into collateral, and redeeming positions after oracle resolution.

## Motivation

Prediction markets have demonstrated product-market fit through platforms like Polymarket. The Gnosis Conditional Tokens Framework from 2019 pioneered the core primitives of splitting, merging, and redeeming positions based on oracle outcomes. However, there is no formal ERC standard, limiting interoperability across implementations.

To enable a thriving ecosystem of prediction markets and futarchy governance, we need a standard interface. This ERC addresses this through three core operations:

1. **Condition Preparation**: Registers a condition with an oracle, question identifier, and outcome count.
2. **Position Splitting & Merging**: Converts collateral into outcome tokens (split) or recombines them (merge).
3. **Redemption**: Token holders claim collateral proportional to the reported payout weights after oracle resolution.

This ERC formalizes patterns that the prediction market industry has battle-tested for years. Providing a unified interface will accelerate adoption across chains and applications.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
interface IConditionalTokens is IERC6909 {
    // Events
    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount
    );

    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    event PositionSplit(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    event PositionsMerge(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );

    // Core functions
    function prepareCondition(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external;

    function reportPayouts(
        bytes32 questionId,
        uint256[] calldata payouts
    ) external;

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    // View functions
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256);

    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external pure returns (bytes32);

    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external view returns (bytes32);

    function getPositionId(
        IERC20 collateralToken,
        bytes32 collectionId
    ) external pure returns (uint256);
}
```

### Methods

#### prepareCondition

Initializes a new condition with a fixed number of outcomes. The function generates a `conditionId` as `keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))` and initializes a payout vector associated with the `conditionId`.

**Parameters:**

- `oracle`: Account used to resolve a condition by calling `reportPayouts`. The `conditionId` is bound to the oracle address, so only that oracle can resolve the condition.
- `questionId`: Identifier for the question to be answered by `oracle`.
- `outcomeSlotCount`: Number of outcomes for a condition. MUST be greater than 1 and less than or equal to 256.

**Behavior:**

- MUST revert if `outcomeSlotCount <= 1` or `outcomeSlotCount > 256`.
- MUST revert if the condition already exists.
- MUST emit `ConditionPreparation` on success.

```solidity
function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external
```

#### reportPayouts

Oracle resolves a condition by calling this function to report payouts for each outcome.

**Parameters:**

- `questionId`: Identifier for the question being resolved.
- `payouts`: Integer weights per outcome slot. The payout fraction for outcome slot `i` is `payouts[i] / sum(payouts)`.

**Behavior:**

- `msg.sender` is enforced as the oracle because `conditionId` is derived from `(msg.sender, questionId, payouts.length)`.
- MUST revert if the condition does not exist.
- MUST revert if the condition is already resolved.
- MUST revert if all payout values are zero.
- MUST emit `ConditionResolution` on success.

```solidity
function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external
```

#### splitPosition

Converts one parent stake into multiple child outcome positions. This either transfers `amount` collateral from the message sender (when splitting from collateral) or burns `amount` of parent position tokens (when splitting a nested position).

**Parameters:**

- `collateralToken`: The address of the position's backing collateral token.
- `parentCollectionId`: Either `bytes32(0)` signifying the position is backed by collateral, or identifier of the parent collection (for nested positions).
- `conditionId`: Condition being split on.
- `partition`: Array of disjoint index sets defining a non-trivial partition of the outcome slots.
- `amount`: Amount of collateral (if `parentCollectionId == bytes32(0)`) or parent position tokens to convert.

**Partition Encoding:**

Each element in the partition array is a bitmask where bit `i` indicates inclusion of outcome `i`. For a condition with 3 outcomes (indexed 0, 1, 2):

- `0b001` (1) = outcome 0 only
- `0b010` (2) = outcome 1 only
- `0b100` (4) = outcome 2 only
- `0b011` (3) = outcomes 0 and 1 combined
- `0b110` (6) = outcomes 1 and 2 combined

A valid partition must be:

1. Non-trivial: `partition.length > 1`
2. Disjoint: For all pairs `(i, j)` where `i != j`, `partition[i] & partition[j] == 0`
3. Complete (for full splits): `partition[0] | partition[1] | ... == (1 << outcomeSlotCount) - 1`

**Example:** For a 2-outcome condition ("Yes"/"No"), partition `[0b01, 0b10]` creates separate "Yes" and "No" position tokens.

**Behavior:**

- MUST revert if partition is trivial (length <= 1).
- MUST revert if partition elements are not disjoint.
- MUST revert if any partition element is zero or exceeds the outcome slot count.
- MUST emit `PositionSplit` on success.

```solidity
function splitPosition(
    IERC20 collateralToken,
    bytes32 parentCollectionId,
    bytes32 conditionId,
    uint256[] calldata partition,
    uint256 amount
) external
```

#### mergePositions

The inverse of `splitPosition`: burns multiple child positions to recreate a parent position or recover collateral.

**Parameters:**

- `collateralToken`: The address of the position's backing collateral token.
- `parentCollectionId`: Either `bytes32(0)` signifying the position is backed by collateral, or identifier of the parent collection (for nested positions).
- `conditionId`: Condition being merged on.
- `partition`: Array of disjoint index sets defining a non-trivial partition of the outcome slots.
- `amount`: Amount of each child position to burn.

**Behavior:**

- If partition covers the full index set: collateral is returned (if `parentCollectionId == bytes32(0)`) or `amount` of parent position tokens are minted.
- If partition covers only a subset: `amount` of the merged subset position token is minted.
- MUST emit `PositionsMerge` on success.

```solidity
function mergePositions(
    IERC20 collateralToken,
    bytes32 parentCollectionId,
    bytes32 conditionId,
    uint256[] calldata partition,
    uint256 amount
) external
```

#### redeemPositions

After a condition is resolved, redeems outcome position tokens for their payout share.

**Parameters:**

- `collateralToken`: The address of the position's backing collateral token.
- `parentCollectionId`: Either `bytes32(0)` for direct redemption to collateral, or identifier of the parent collection for nested redemption.
- `conditionId`: Resolved condition.
- `indexSets`: List of outcome collections (bitmasks) whose positions the caller wants to redeem.

**Behavior:**

For each `indexSet`:

1. Computes the caller's balance of the corresponding `positionId`
2. Burns the position tokens
3. Calculates `payout += balance * payoutNumerator(indexSet) / payoutDenominator`

Then either transfers collateral payout to caller (if `parentCollectionId == bytes32(0)`) or mints parent position tokens (if nested).

- MUST revert if the condition is not resolved.
- MUST emit `PayoutRedemption` on success.

```solidity
function redeemPositions(
    IERC20 collateralToken,
    bytes32 parentCollectionId,
    bytes32 conditionId,
    uint256[] calldata indexSets
) external
```

#### getOutcomeSlotCount

Returns the outcome slot count of a `conditionId`.

```solidity
function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256)
```

#### getConditionId

Returns the generated `conditionId` as `keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))`.

**Parameters:**

- `oracle`: The account assigned to report the result.
- `questionId`: An identifier for the question to be answered by the oracle.
- `outcomeSlotCount`: The number of outcome slots for this condition.

```solidity
function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external pure returns (bytes32)
```

#### getCollectionId

Returns `collectionId` constructed by combining a parent collection and an outcome collection.

**Parameters:**

- `parentCollectionId`: Collection ID of the parent outcome collection, or `bytes32(0)` if there's no parent.
- `conditionId`: Condition ID of the outcome collection to combine with the parent.
- `indexSet`: Index set of the outcome collection to combine with the parent.

```solidity
function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet) external view returns (bytes32)
```

#### getPositionId

Returns `positionId` from collateral token and outcome collection.

**Parameters:**

- `collateralToken`: Collateral token which backs the position.
- `collectionId`: ID of the outcome collection associated with this position.

```solidity
function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint256)
```

### Events

#### ConditionPreparation

Emitted when a new condition is initialized.

```solidity
event ConditionPreparation(
    bytes32 indexed conditionId,
    address indexed oracle,
    bytes32 indexed questionId,
    uint256 outcomeSlotCount
)
```

#### ConditionResolution

Emitted when an oracle executes `reportPayouts` for a `questionId`.

```solidity
event ConditionResolution(
    bytes32 indexed conditionId,
    address indexed oracle,
    bytes32 indexed questionId,
    uint256 outcomeSlotCount,
    uint256[] payoutNumerators
)
```

#### PositionSplit

Emitted when a user splits collateral or a position into multiple outcome positions.

```solidity
event PositionSplit(
    address indexed stakeholder,
    IERC20 collateralToken,
    bytes32 indexed parentCollectionId,
    bytes32 indexed conditionId,
    uint256[] partition,
    uint256 amount
)
```

#### PositionsMerge

Emitted when a user merges multiple positions back into a parent position or collateral.

```solidity
event PositionsMerge(
    address indexed stakeholder,
    IERC20 collateralToken,
    bytes32 indexed parentCollectionId,
    bytes32 indexed conditionId,
    uint256[] partition,
    uint256 amount
)
```

#### PayoutRedemption

Emitted when a user redeems positions after resolution.

```solidity
event PayoutRedemption(
    address indexed redeemer,
    IERC20 indexed collateralToken,
    bytes32 indexed parentCollectionId,
    bytes32 conditionId,
    uint256[] indexSets,
    uint256 payout
)
```

## Rationale

### Why ERC-6909 over ERC-1155?

ERC-6909 provides a minimal multi-token interface that is better suited for conditional tokens because:

1. **Simpler interface**: ERC-6909 removes batch operations and callback hooks that add complexity without benefit for prediction markets.
2. **Gas efficiency**: The streamlined interface reduces deployment and interaction costs.
3. **No mandatory callbacks**: ERC-1155 requires receiver callbacks which can be exploited for reentrancy.

### Why 256 Outcome Limit?

The 256 outcome limit is chosen because:

1. **Bitmask representation**: Outcomes are encoded as bitmasks in `uint256` values. 256 outcomes require 256 bits, fitting exactly in a single word.
2. **Practical sufficiency**: Real-world prediction markets rarely need more than a few dozen outcomes.
3. **Gas considerations**: Operations on larger outcome sets become prohibitively expensive.

### Why keccak256 for conditionId?

Using `keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))` ensures:

1. **Deterministic derivation**: Anyone can compute the `conditionId` from public parameters.
2. **Oracle binding**: The oracle address is embedded, preventing unauthorized resolution.
3. **Collision resistance**: Different parameter combinations produce unique IDs.

### Why Nested Positions?

Nested positions (via `parentCollectionId`) enable complex conditional logic such as "If ETH > $3000, what is the probability ETH > $4000?" This composability is essential for:

1. **Conditional-on-conditional markets**: Questions that only matter if other conditions are met.
2. **Scalar markets**: Representing continuous outcomes through multiple nested conditions.
3. **Combinatorial markets**: Expressing complex interdependent outcomes.

## Backwards Compatibility

This ERC formalizes the interface pioneered by the Gnosis Conditional Tokens Framework (CTF). Key differences from the original CTF:

1. **ERC-6909 vs ERC-1155**: This standard uses ERC-6909 for position tokens instead of ERC-1155.
2. **Standardized interface**: The original CTF had implementation-specific extensions; this ERC defines the minimal required interface.

Existing CTF deployments are not directly compatible but follow the same conceptual model. Migration requires redeploying positions on a compliant implementation.

## Reference Implementation

A reference implementation is available at: [TODO: Add repository link]

## Security Considerations

### Oracle Trust

The oracle has absolute authority over payout distribution. A malicious or compromised oracle can direct all collateral to chosen outcomes with no on-chain dispute mechanism.

**Mitigations:**

- Use multi-sig oracles requiring multiple parties to agree.
- Implement time-locked reporting with a dispute window.
- Use oracle networks with staking and slashing conditions (e.g., UMA, Chainlink).
- Consider optimistic oracle designs with challenge periods.

### Reentrancy

Functions interacting with collateral tokens via `transfer` and `transferFrom` are susceptible to reentrancy if the token has callbacks (e.g., ERC-777 hooks).

**Mitigations:**

- Implementations MUST follow checks-effects-interactions pattern.
- Implementations SHOULD use reentrancy guards.

### Non-Standard Tokens

Non-standard tokens may cause accounting discrepancies:

- **Fee-on-transfer tokens**: Actual received amount differs from transfer amount.
- **Rebasing tokens**: Balances change outside of transfers.
- **Pausable tokens**: Transfers may unexpectedly revert.

**Mitigations:**

- Implementations SHOULD document supported token types.
- Implementations SHOULD measure actual balance changes rather than trusting transfer amounts.

### Front-Running

Oracle resolution transactions are visible in the mempool. Attackers can front-run `reportPayouts` to acquire winning positions before resolution.

**Mitigations:**

- Use commit-reveal schemes for oracle reporting.
- Submit resolution transactions through private mempools (e.g., Flashbots Protect).
- Implement trading halts before known resolution times.

### Denial of Service

`prepareCondition` is permissionless and allocates storage. Attackers can spam condition creation to bloat contract storage.

**Mitigations:**

- Require deposits for condition creation (refundable on resolution).
- Restrict creation to authorized registries.
- Implement rate limiting per address.

### Integer Overflow in Partition Operations

Partition bitmask operations must be bounds-checked to prevent overflow.

**Mitigations:**

- Validate that no index set exceeds `(1 << outcomeSlotCount) - 1`.
- Check for zero index sets in partitions.

### Payout Precision and Rounding

Payout calculations involve division which can leave dust amounts unredeemable due to rounding errors.

**Mitigations:**

- Use consistent rounding (floor) to ensure total payouts never exceed collateral.
- Document that small dust amounts may remain in the contract.
- Consider implementing a sweep function for residual collateral.

### Condition Immutability

Once created, conditions cannot be modified or deleted.

**Guarantees:**

- `prepareCondition` MUST revert if called with parameters matching an existing condition.
- `outcomeSlotCount` is immutable after creation.
- Oracle address binding is permanent.
