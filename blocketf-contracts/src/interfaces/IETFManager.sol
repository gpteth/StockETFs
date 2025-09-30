// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IETFManager {
    struct DepositInfo {
        uint256 usdtAmount;     // 输入的USDT数量
        uint256 shares;         // 获得的份额
        uint256[] swapAmounts;  // 各资产交换数量
        uint256 timestamp;      // 时间戳
    }

    struct WithdrawInfo {
        uint256 shares;         // 销毁的份额
        uint256 usdtAmount;     // 获得的USDT数量
        uint256[] swapAmounts;  // 各资产交换数量
        uint256 timestamp;      // 时间戳
    }

    // Events
    event Deposited(
        address indexed user,
        uint256 usdtAmount,
        uint256 shares,
        uint256[] amounts
    );

    event Withdrawn(
        address indexed user,
        uint256 shares,
        uint256 usdtAmount,
        uint256[] amounts
    );

    event SlippageUpdated(uint256 maxSlippage);
    event RouterUpdated(address newRouter);
    event EmergencyWithdraw(address indexed token, uint256 amount, address to);

    // User functions
    function depositUSDT(uint256 usdtAmount, uint256 minShares) external returns (uint256 shares);
    function withdrawToUSDT(uint256 shares, uint256 minUSDT) external returns (uint256 usdtAmount);

    // Advanced functions
    function depositWithAssets(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256 minShares
    ) external returns (uint256 shares);

    function withdrawAssets(
        uint256 shares,
        uint256[] calldata minAmounts
    ) external returns (uint256[] memory amounts);

    // View functions
    function calculateDepositShares(uint256 usdtAmount) external view returns (uint256 shares);
    function calculateWithdrawUSDT(uint256 shares) external view returns (uint256 usdtAmount);
    function getOptimalSwapPath(address tokenIn, address tokenOut, uint256 amount)
        external view returns (address[] memory path, uint256 expectedOut);

    // Admin functions
    function setMaxSlippage(uint256 maxSlippage) external;
    function setRouter(address newRouter) external;
    function emergencyWithdraw(address token, uint256 amount, address to) external;

    // View functions
    function getETF() external view returns (address);
    function getRouter() external view returns (address);
    function getUSDT() external view returns (address);
    function getMaxSlippage() external view returns (uint256);
}