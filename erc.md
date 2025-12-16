---
eip: XXX
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