// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BlockETFCore.sol";
import "../src/oracles/ChainlinkPriceOracle.sol";
import "../src/router/ETFRouterV1.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title InitializeETF
 * @notice 初始化股票 ETF（配置资产、权重、初始流动性）
 * @dev 使用方法:
 * 1. 在 .env 文件中设置必要的环境变量
 * 2. 执行: forge script script/InitializeETF.s.sol:InitializeETF --rpc-url <RPC_URL> --broadcast
 */
contract InitializeETF is Script {
    // 从环境变量读取已部署的合约地址
    function getETFCore() internal view returns (address) {
        return vm.envAddress("ETF_CORE_ADDRESS");
    }

    function getOracle() internal view returns (address) {
        return vm.envAddress("ORACLE_ADDRESS");
    }

    function getRouter() internal view returns (address) {
        return vm.envAddress("ROUTER_ADDRESS");
    }

    // 股票代币地址（从环境变量读取或使用默认值）
    function getTSLA() internal view returns (address) {
        return vm.envOr("TSLA_TOKEN", address(0));
    }

    function getAAPL() internal view returns (address) {
        return vm.envOr("AAPL_TOKEN", address(0));
    }

    function getGOOGL() internal view returns (address) {
        return vm.envOr("GOOGL_TOKEN", address(0));
    }

    function getMSFT() internal view returns (address) {
        return vm.envOr("MSFT_TOKEN", address(0));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Initializer address:", deployer);
        console.log("Initializing Stock ETF...");

        // 获取已部署的合约
        StockETFCore etfCore = StockETFCore(getETFCore());
        ChainlinkPriceOracle oracle = ChainlinkPriceOracle(getOracle());

        console.log("\nContract addresses:");
        console.log("ETF Core:", address(etfCore));
        console.log("Oracle:", address(oracle));

        // 准备资产列表
        address tsla = getTSLA();
        address aapl = getAAPL();
        address googl = getGOOGL();
        address msft = getMSFT();

        require(tsla != address(0), "TSLA token not set");
        require(aapl != address(0), "AAPL token not set");
        require(googl != address(0), "GOOGL token not set");
        require(msft != address(0), "MSFT token not set");

        address[] memory assets = new address[](4);
        assets[0] = tsla;
        assets[1] = aapl;
        assets[2] = googl;
        assets[3] = msft;

        // 设置权重（均等权重：各 25%）
        uint32[] memory weights = new uint32[](4);
        weights[0] = 2500; // 25%
        weights[1] = 2500; // 25%
        weights[2] = 2500; // 25%
        weights[3] = 2500; // 25%

        // 准备初始金额（根据实际情况调整）
        // 这里假设每个股票代币都是 18 位小数
        uint256[] memory initialAmounts = new uint256[](4);
        initialAmounts[0] = 1e18; // 1 TSLA
        initialAmounts[1] = 1e18; // 1 AAPL
        initialAmounts[2] = 1e18; // 1 GOOGL
        initialAmounts[3] = 1e18; // 1 MSFT

        // 初始 ETF 份额供应量
        uint256 initialSupply = 1000e18; // 1000 ETF shares

        vm.startBroadcast(deployerPrivateKey);

        // 1. 授权 ETF Core 使用股票代币
        console.log("\n1. Approving tokens for ETF Core...");
        for (uint i = 0; i < assets.length; i++) {
            IERC20 token = IERC20(assets[i]);
            uint256 balance = token.balanceOf(deployer);
            console.log("   Token balance:", balance);

            if (balance < initialAmounts[i]) {
                console.log("   WARNING: Insufficient balance for token", assets[i]);
                console.log("   Required:", initialAmounts[i]);
                console.log("   Available:", balance);
                revert("Insufficient token balance");
            }

            token.approve(address(etfCore), initialAmounts[i]);
            console.log("   Approved", initialAmounts[i], "for", assets[i]);
        }

        // 2. 初始化 ETF
        console.log("\n2. Initializing ETF...");
        etfCore.initialize(assets, weights, initialAmounts, initialSupply);
        console.log("   ETF initialized successfully!");

        // 3. 验证初始化
        console.log("\n3. Verifying initialization...");
        uint256 totalValue = etfCore.getTotalValue();
        uint256 shareValue = etfCore.getShareValue();
        uint256 supply = IERC20(address(etfCore)).totalSupply();

        console.log("   Total Value (USD):", totalValue / 1e18);
        console.log("   Share Value (USD):", shareValue / 1e18);
        console.log("   Total Supply:", supply / 1e18);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("ETF Initialization Complete!");
        console.log("========================================");
        console.log("You can now:");
        console.log("1. Mint ETF shares using: router.mintWithUSDT()");
        console.log("2. Burn ETF shares using: router.burnToUSDT()");
        console.log("3. Monitor ETF value: etfCore.getTotalValue()");
        console.log("========================================");
    }
}