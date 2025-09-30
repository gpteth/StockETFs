// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBlockETFCore {
    struct AssetInfo {
        address token;
        uint32 weight; // 基点，10000 = 100%
        uint224 reserve; // 当前储备量
    }

    struct FeeInfo {
        uint32 withdrawFee; // 赎回费率（基点）
        uint128 managementFeeRate; // 每秒费率（精度1e27）
        uint256 accumulatedFee; // 累积的管理费
        uint256 lastCollectTime; // 上次收取时间
    }

    // Events
    event Mint(address indexed to, uint256 shares, uint256[] amounts);
    event Burn(address indexed from, uint256 shares, uint256[] amounts);
    event AssetConfigured(address[] tokens, uint32[] weights);
    event FeeUpdated(uint32 withdrawFee, uint256 annualManagementFeeBps);
    event ManagementFeeCollected(
        address indexed collector,
        uint256 shares,
        uint256 feeValue
    );
    event PriceOracleUpdated(address indexed oracle);
    event RebalancerUpdated(address indexed rebalancer);
    event RebalanceThresholdUpdated(uint256 threshold);
    event Rebalanced(uint256[] oldWeights, uint256[] newWeights);
    event Paused();
    event Unpaused();

    // Core functions - 任何人都可以调用
    function mint(address to) external returns (uint256 shares);

    function mintExactShares(
        uint256 shares,
        address to
    ) external returns (uint256[] memory amounts);

    function burn(
        uint256 shares,
        address to
    ) external returns (uint256[] memory amounts);

    // Asset management - 仅管理员
    function configureAssets(
        address[] calldata tokens,
        uint32[] calldata weights
    ) external;

    function flashRebalance(address receiver, bytes calldata data) external;

    function getRebalanceInfo()
        external
        view
        returns (
            uint256[] memory currentWeights,
            uint256[] memory targetWeights,
            bool needsRebalance
        );

    // Fee management - 仅管理员
    function setFees(
        uint32 withdrawFee,
        uint256 annualManagementFeeBps
    ) external;

    function collectManagementFee() external returns (uint256);

    // Price Oracle management - 仅管理员
    function setPriceOracle(address oracle) external;

    // Rebalancer management - 仅管理员
    function setRebalancer(address rebalancer) external;

    function setRebalanceThreshold(uint256 threshold) external;

    // Emergency controls - 仅管理员
    function pause() external;

    function unpause() external;

    // View functions
    function getAssets() external view returns (AssetInfo[] memory);

    function getFeeInfo() external view returns (FeeInfo memory);

    function getTotalValue() external view returns (uint256);

    function getShareValue() external view returns (uint256);

    function calculateMintShares(
        uint256[] calldata amounts
    ) external view returns (uint256);

    function calculateBurnAmounts(
        uint256 shares
    ) external view returns (uint256[] memory);

    function calculateRequiredAmounts(
        uint256 shares
    ) external view returns (uint256[] memory);

    function getAnnualManagementFee() external view returns (uint256); // 返回年化费率（基点）

    function isPaused() external view returns (bool);
}
