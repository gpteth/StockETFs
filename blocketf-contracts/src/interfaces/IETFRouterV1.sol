// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IETFRouterV1 {
    // Events
    event MintWithUSDT(
        address indexed user,
        uint256 usdtAmount,
        uint256 sharesReceived
    );
    event BurnToUSDT(
        address indexed user,
        uint256 sharesBurned,
        uint256 usdtReceived
    );

    // Main functions
    function mintWithUSDT(
        uint256 usdtAmount,
        uint256 minShares,
        uint256 deadline
    ) external returns (uint256 shares);

    function burnToUSDT(
        uint256 shares,
        uint256 minUSDT,
        uint256 deadline
    ) external returns (uint256 usdtAmount);

    // View functions for estimation
    function estimateUSDTForMint(
        uint256 shares
    ) external view returns (uint256 usdtNeeded);

    function estimateUSDTFromBurn(
        uint256 shares
    ) external view returns (uint256 usdtAmount);

    function estimateSharesFromUSDT(
        uint256 usdtAmount
    ) external view returns (uint256 shares);
}