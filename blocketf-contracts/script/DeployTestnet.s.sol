// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BlockETFCore.sol";
import "../src/oracles/ChainlinkPriceOracle.sol";
import "../src/router/ETFRouterV1.sol";
import "../src/mocks/MockStockToken.sol";
import "../src/mocks/MockChainlinkAggregator.sol";

/**
 * @title DeployTestnet
 * @notice 部署到 BSC 测试网的完整脚本
 * @dev 包含 Mock 股票代币和 Mock Chainlink 聚合器
 *
 * 使用方法:
 * source .env.bsc-testnet
 * forge script script/DeployTestnet.s.sol:DeployTestnet \
 *   --rpc-url $BSC_TESTNET_RPC \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BSCSCAN_API_KEY \
 *   -vvvv
 */
contract DeployTestnet is Script {
    // BSC 测试网地址
    address constant USDT = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd;
    address constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address constant PANCAKE_V3_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
    address constant PANCAKE_V3_QUOTER = 0xbC203d7f83677c7ed3F7acEc959963E7F4ECC5C2;
    address constant PANCAKE_V2_ROUTER = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    // 股票初始价格（8 位小数）
    int256 constant TSLA_PRICE = 25000000000;  // $250.00
    int256 constant AAPL_PRICE = 18000000000;  // $180.00
    int256 constant GOOGL_PRICE = 14000000000; // $140.00
    int256 constant MSFT_PRICE = 38000000000;  // $380.00

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("BSC Testnet Deployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "BNB");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ============================================
        // 1. 部署 Mock 股票代币
        // ============================================
        console.log("1. Deploying Mock Stock Tokens...");

        MockStockToken tsla = new MockStockToken("Tesla Token", "TSLA", 18);
        console.log("   TSLA Token:", address(tsla));

        MockStockToken aapl = new MockStockToken("Apple Token", "AAPL", 18);
        console.log("   AAPL Token:", address(aapl));

        MockStockToken googl = new MockStockToken("Google Token", "GOOGL", 18);
        console.log("   GOOGL Token:", address(googl));

        MockStockToken msft = new MockStockToken("Microsoft Token", "MSFT", 18);
        console.log("   MSFT Token:", address(msft));

        // ============================================
        // 2. 部署 Mock Chainlink 聚合器
        // ============================================
        console.log("\n2. Deploying Mock Chainlink Aggregators...");

        MockChainlinkAggregator tslaFeed = new MockChainlinkAggregator(
            8,
            "TSLA / USD",
            TSLA_PRICE
        );
        console.log("   TSLA Feed:", address(tslaFeed));

        MockChainlinkAggregator aaplFeed = new MockChainlinkAggregator(
            8,
            "AAPL / USD",
            AAPL_PRICE
        );
        console.log("   AAPL Feed:", address(aaplFeed));

        MockChainlinkAggregator googlFeed = new MockChainlinkAggregator(
            8,
            "GOOGL / USD",
            GOOGL_PRICE
        );
        console.log("   GOOGL Feed:", address(googlFeed));

        MockChainlinkAggregator msftFeed = new MockChainlinkAggregator(
            8,
            "MSFT / USD",
            MSFT_PRICE
        );
        console.log("   MSFT Feed:", address(msftFeed));

        // ============================================
        // 3. 部署 Chainlink 价格预言机
        // ============================================
        console.log("\n3. Deploying ChainlinkPriceOracle...");
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(USDT);
        console.log("   Oracle:", address(oracle));

        // ============================================
        // 4. 配置价格数据源
        // ============================================
        console.log("\n4. Configuring Price Feeds...");

        address[] memory tokens = new address[](4);
        tokens[0] = address(tsla);
        tokens[1] = address(aapl);
        tokens[2] = address(googl);
        tokens[3] = address(msft);

        address[] memory feeds = new address[](4);
        feeds[0] = address(tslaFeed);
        feeds[1] = address(aaplFeed);
        feeds[2] = address(googlFeed);
        feeds[3] = address(msftFeed);

        oracle.setPriceFeedsBatch(tokens, feeds);
        console.log("   Price feeds configured for 4 tokens");

        // ============================================
        // 5. 部署 ETF Core
        // ============================================
        console.log("\n5. Deploying StockETFCore...");
        StockETFCore etfCore = new StockETFCore("Tech Stock ETF", "TECH");
        console.log("   ETF Core:", address(etfCore));

        // ============================================
        // 6. 设置价格预言机
        // ============================================
        console.log("\n6. Setting Price Oracle...");
        etfCore.setPriceOracle(address(oracle));
        console.log("   Price oracle set");

        // ============================================
        // 7. 配置费率
        // ============================================
        console.log("\n7. Configuring Fees...");
        etfCore.setFees(100, 200); // 1% 赎回费，2% 年化管理费
        console.log("   Fees: 1% withdraw, 2% annual management");

        // ============================================
        // 8. 初始化 ETF
        // ============================================
        console.log("\n8. Initializing ETF...");

        uint32[] memory weights = new uint32[](4);
        weights[0] = 2500; // 25% TSLA
        weights[1] = 2500; // 25% AAPL
        weights[2] = 2500; // 25% GOOGL
        weights[3] = 2500; // 25% MSFT

        uint256[] memory initialAmounts = new uint256[](4);
        initialAmounts[0] = 100e18; // 100 TSLA
        initialAmounts[1] = 100e18; // 100 AAPL
        initialAmounts[2] = 100e18; // 100 GOOGL
        initialAmounts[3] = 100e18; // 100 MSFT

        // 授权
        tsla.approve(address(etfCore), 100e18);
        aapl.approve(address(etfCore), 100e18);
        googl.approve(address(etfCore), 100e18);
        msft.approve(address(etfCore), 100e18);

        // 初始化（1000 ETF 份额 + 1000 最小流动性）
        etfCore.initialize(tokens, weights, initialAmounts, 1000e18 + 1000);
        console.log("   ETF initialized with 1000 shares");

        // ============================================
        // 9. 部署 Router
        // ============================================
        console.log("\n9. Deploying ETFRouterV1...");
        ETFRouterV1 router = new ETFRouterV1(
            address(etfCore),
            PANCAKE_V3_ROUTER,
            PANCAKE_V3_QUOTER,
            address(oracle),
            PANCAKE_V2_ROUTER,
            USDT,
            WBNB
        );
        console.log("   Router:", address(router));

        vm.stopBroadcast();

        // ============================================
        // 部署摘要
        // ============================================
        console.log("\n========================================");
        console.log("Deployment Summary");
        console.log("========================================");
        console.log("");
        console.log("Mock Tokens:");
        console.log("  TSLA:", address(tsla));
        console.log("  AAPL:", address(aapl));
        console.log("  GOOGL:", address(googl));
        console.log("  MSFT:", address(msft));
        console.log("");
        console.log("Mock Chainlink Feeds:");
        console.log("  TSLA/USD:", address(tslaFeed));
        console.log("  AAPL/USD:", address(aaplFeed));
        console.log("  GOOGL/USD:", address(googlFeed));
        console.log("  MSFT/USD:", address(msftFeed));
        console.log("");
        console.log("Core Contracts:");
        console.log("  ChainlinkPriceOracle:", address(oracle));
        console.log("  StockETFCore:", address(etfCore));
        console.log("  ETFRouterV1:", address(router));
        console.log("");
        console.log("ETF Info:");
        console.log("  Total Value:", etfCore.getTotalValue() / 1e18, "USD");
        console.log("  Share Value:", etfCore.getShareValue() / 1e18, "USD");
        console.log("  Total Supply:", etfCore.totalSupply() / 1e18, "shares");
        console.log("");
        console.log("========================================");
        console.log("Testnet URLs:");
        console.log("========================================");
        console.log("BSCScan Testnet: https://testnet.bscscan.com");
        console.log("Faucet: https://testnet.bnbchain.org/faucet-smart");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Get testnet BNB from faucet");
        console.log("2. Mint some stock tokens to your address");
        console.log("3. Test minting ETF shares");
        console.log("4. Test burning ETF shares");
        console.log("========================================");
    }
}