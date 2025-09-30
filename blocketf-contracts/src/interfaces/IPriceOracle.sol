// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceOracle {
    struct PriceInfo {
        uint256 price;      // 价格（以USDT为基准，18位小数）
        uint256 timestamp;  // 价格更新时间戳
        bool isValid;       // 价格是否有效
    }

    // Events
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event PriceFeedAdded(address indexed token, address feed);
    event PriceFeedRemoved(address indexed token);

    // Core functions
    function getPrice(address token) external view returns (uint256 price);
    function getPrices(address[] calldata tokens) external view returns (uint256[] memory prices);
    function getPriceInfo(address token) external view returns (PriceInfo memory);

    // Calculate functions
    function calculateValue(address token, uint256 amount) external view returns (uint256 value);
    function calculateTotalValue(address[] calldata tokens, uint256[] calldata amounts)
        external view returns (uint256 totalValue);

    // Admin functions
    function setPriceFeed(address token, address feed) external;
    function removePriceFeed(address token) external;
    function updatePrice(address token) external;
    function updatePrices(address[] calldata tokens) external;

    // View functions
    function isPriceValid(address token) external view returns (bool);
    function getLastUpdateTime(address token) external view returns (uint256);
    function getStalenessThreshold() external view returns (uint256);
}