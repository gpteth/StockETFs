// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BlockETFCore.sol";
import "../src/oracles/ChainlinkPriceOracle.sol";
import "../src/router/ETFRouterV1.sol";

/**
 * @title DeployStockETF
 * @notice 部署完整的股票 ETF 系统（包含 Chainlink 价格预言机）
 * @dev 使用方法:
 * forge script script/DeployStockETF.s.sol:DeployStockETF --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployStockETF is Script {
    // BSC Mainnet 地址配置
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // PancakeSwap V3 Router (BSC Mainnet)
    address constant PANCAKE_V3_ROUTER = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant PANCAKE_V3_QUOTER = 0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997;

    // PancakeSwap V2 Router (BSC Mainnet)
    address constant PANCAKE_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Chainlink Price Feeds (BSC Mainnet)
    address constant CHAINLINK_TSLA_USD = 0x1B329402Cb1825C6F30A0d92aB9E2862BE47333f;
    address constant CHAINLINK_AAPL_USD = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
    address constant CHAINLINK_GOOGL_USD = 0xeDA73F8acb669274B15A977Cb0cdA57a84F18c2a;
    address constant CHAINLINK_MSFT_USD = 0x5D209cE1fBABeAA8E6f9De4514A74FFB4b34560F;

    // 股票代币地址（需要替换为实际的代币化股票地址）
    // 这些是示例地址，实际部署时需要替换
    address TSLA_TOKEN;
    address AAPL_TOKEN;
    address GOOGL_TOKEN;
    address MSFT_TOKEN;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deploying Stock ETF System with Chainlink integration...");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 Chainlink 价格预言机
        console.log("\n1. Deploying ChainlinkPriceOracle...");
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(USDT);
        console.log("   ChainlinkPriceOracle deployed at:", address(oracle));

        // 2. 配置股票代币的价格数据源
        console.log("\n2. Setting up Chainlink price feeds...");

        // 注意：这里需要实际的股票代币地址
        // 如果你有实际的股票代币合约，请替换下面的地址
        address[] memory tokens = new address[](4);
        address[] memory feeds = new address[](4);

        // 示例配置（需要替换为实际的股票代币地址）
        if (TSLA_TOKEN != address(0)) {
            tokens[0] = TSLA_TOKEN;
            feeds[0] = CHAINLINK_TSLA_USD;

            tokens[1] = AAPL_TOKEN;
            feeds[1] = CHAINLINK_AAPL_USD;

            tokens[2] = GOOGL_TOKEN;
            feeds[2] = CHAINLINK_GOOGL_USD;

            tokens[3] = MSFT_TOKEN;
            feeds[3] = CHAINLINK_MSFT_USD;

            oracle.setPriceFeedsBatch(tokens, feeds);
            console.log("   Price feeds configured for 4 stock tokens");
        } else {
            console.log("   WARNING: Stock token addresses not set, skipping price feed setup");
            console.log("   You need to call setPriceFeedsBatch manually with actual token addresses");
        }

        // 3. 部署 ETF Core 合约
        console.log("\n3. Deploying StockETFCore...");
        StockETFCore etfCore = new StockETFCore("Tech Stock ETF", "TECH");
        console.log("   StockETFCore deployed at:", address(etfCore));

        // 4. 设置价格预言机
        console.log("\n4. Setting price oracle for ETF Core...");
        etfCore.setPriceOracle(address(oracle));
        console.log("   Price oracle set successfully");

        // 5. 配置费率
        console.log("\n5. Configuring fees...");
        etfCore.setFees(
            100,  // 1% 赎回费
            200   // 2% 年化管理费
        );
        console.log("   Fees configured: 1% withdraw fee, 2% annual management fee");

        // 6. 部署 Router 合约
        console.log("\n6. Deploying ETFRouterV1...");
        ETFRouterV1 router = new ETFRouterV1(
            address(etfCore),
            PANCAKE_V3_ROUTER,
            PANCAKE_V3_QUOTER,
            address(oracle),
            PANCAKE_V2_ROUTER,
            USDT,
            WBNB
        );
        console.log("   ETFRouterV1 deployed at:", address(router));

        vm.stopBroadcast();

        // 打印部署摘要
        console.log("\n========================================");
        console.log("Deployment Summary");
        console.log("========================================");
        console.log("ChainlinkPriceOracle:", address(oracle));
        console.log("StockETFCore:", address(etfCore));
        console.log("ETFRouterV1:", address(router));
        console.log("========================================");
        console.log("\nNext steps:");
        console.log("1. Set actual stock token addresses");
        console.log("2. Configure price feeds: oracle.setPriceFeedsBatch(tokens, feeds)");
        console.log("3. Initialize ETF: etfCore.initialize(assets, weights, amounts, supply)");
        console.log("4. Configure asset pools: router.setAssetPoolsBatch(assets, pools)");
        console.log("========================================");
    }
}