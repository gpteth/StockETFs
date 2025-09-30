// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Errors {
    // General errors
    error NotInitialized();
    error AlreadyInitialized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidLength();
    error ZeroAmount();
    error ZeroAddress();

    // Asset errors
    error NoAssets();
    error InvalidAsset();
    error InvalidWeight();
    error InvalidTotalWeight();
    error DuplicateAsset();
    error NoNewAssets();
    error InvalidRatio();

    // Mint/Burn errors
    error InvalidShares();
    error InsufficientMintAmount();
    error InsufficientBalance();
    error InvalidRecipient();
    error InsufficientInitialSupply();

    // Fee errors
    error FeeTooHigh();
    error InvalidFeeCollector();

    // Threshold errors
    error ThresholdTooHigh();

    // Configuration errors
    error CannotReconfigureAfterInit();
    error RebalanceNotImplemented();

    // Rebalance errors
    error RebalanceNotNeeded();
    error InvalidRebalance();
    error ExcessiveLoss();

    // Price Oracle errors
    error InvalidOracle();
    error OracleNotSet();
    error InvalidPrice();

    // Access control
    error Unauthorized();
}