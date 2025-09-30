# 股票 ETF + Chainlink 集成

## 🎯 概述

本项目实现了一个完整的链上股票 ETF 系统，使用 **Chainlink 价格预言机**获取实时股票价格数据。

## 📁 项目结构

```
blocketf-contracts/
├── src/
│   ├── BlockETFCore.sol              # ETF 核心合约（已重命名为 StockETFCore）
│   ├── oracles/
│   │   └── ChainlinkPriceOracle.sol  # Chainlink 价格预言机
│   ├── router/
│   │   └── ETFRouterV1.sol           # ETF 路由器（USDT 一键购买）
│   └── interfaces/
│       ├── IPriceOracle.sol          # 价格预言机接口
│       └── IStockETFCore.sol         # ETF 核心接口
├── script/
│   ├── DeployStockETF.s.sol          # 部署脚本
│   └── InitializeETF.s.sol           # 初始化脚本
├── test/
│   ├── ChainlinkPriceOracle.t.sol    # 预言机测试
│   └── StockETFIntegration.t.sol     # 集成测试
└── docs/
    └── STOCK_ETF_GUIDE.md            # 详细使用文档
```

## 🚀 快速开始

### 1. 安装依赖

```bash
forge install
```

依赖包括：
- OpenZeppelin Contracts
- Chainlink Brownie Contracts
- Forge Standard Library

### 2. 编译合约

```bash
forge build
```

### 3. 运行测试

```bash
# 运行所有测试
forge test -vv

# 只运行 Chainlink 预言机测试
forge test --match-contract ChainlinkPriceOracleTest -vv

# 只运行 ETF 集成测试
forge test --match-contract StockETFIntegrationTest -vv
```

**测试结果**: ✅ 29 个测试全部通过

```
Ran 18 tests for ChainlinkPriceOracle - ALL PASSED ✅
Ran 11 tests for StockETFIntegration - ALL PASSED ✅
```

## 📦 部署步骤

### 前置条件

1. 准备 `.env` 文件（参考 `.env.example`）
2. 确保有足够的 BNB 支付 gas 费
3. 获取实际的股票代币合约地址

### 步骤 1: 部署系统

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑 .env，填入你的私钥和配置
vim .env

# 部署到 BSC 主网
forge script script/DeployStockETF.s.sol:DeployStockETF \
  --rpc-url $BSC_MAINNET_RPC \
  --broadcast \
  --verify

# 或部署到测试网
forge script script/DeployStockETF.s.sol:DeployStockETF \
  --rpc-url $BSC_TESTNET_RPC \
  --broadcast
```

部署后会输出：
- ✅ ChainlinkPriceOracle 地址
- ✅ StockETFCore 地址
- ✅ ETFRouterV1 地址

### 步骤 2: 配置价格数据源

```bash
# 在 .env 中设置已部署的合约地址和股票代币地址
ORACLE_ADDRESS=0x...
TSLA_TOKEN=0x...
AAPL_TOKEN=0x...
# ...

# 使用 cast 命令配置价格源
cast send $ORACLE_ADDRESS \
  "setPriceFeedsBatch(address[],address[])" \
  "[$TSLA_TOKEN,$AAPL_TOKEN]" \
  "[$CHAINLINK_TSLA_FEED,$CHAINLINK_AAPL_FEED]" \
  --rpc-url $BSC_MAINNET_RPC \
  --private-key $PRIVATE_KEY
```

### 步骤 3: 初始化 ETF

```bash
# 在 .env 中设置所有必要的地址
ETF_CORE_ADDRESS=0x...
ORACLE_ADDRESS=0x...
ROUTER_ADDRESS=0x...
TSLA_TOKEN=0x...
# ...

# 运行初始化脚本
forge script script/InitializeETF.s.sol:InitializeETF \
  --rpc-url $BSC_MAINNET_RPC \
  --broadcast
```

## 🔗 Chainlink 集成详解

### 核心合约: ChainlinkPriceOracle

```solidity
// src/oracles/ChainlinkPriceOracle.sol
contract ChainlinkPriceOracle is IPriceOracle, Ownable {
    // 价格数据源映射
    mapping(address => AggregatorV3Interface) public priceFeeds;

    // 获取代币价格（18位小数，USDT计价）
    function getPrice(address token) external view returns (uint256);

    // 批量设置价格数据源
    function setPriceFeedsBatch(
        address[] calldata tokens,
        address[] calldata feeds
    ) external;
}
```

### 支持的股票价格源（BSC 主网）

| 股票 | Chainlink Feed 地址 |
|------|-------------------|
| TSLA | `0x1B329402Cb1825C6F30A0d92aB9E2862BE47333f` |
| AAPL | `0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE` |
| GOOGL | `0xeDA73F8acb669274B15A977Cb0cdA57a84F18c2a` |
| MSFT | `0x5D209cE1fBABeAA8E6f9De4514A74FFB4b34560F` |
| AMZN | `0x51d08ca89d3e8c12535BA8AEd33cDf2557ab5b2a` |

### 价格验证机制

ChainlinkPriceOracle 实现了多重安全检查：

1. ✅ **时效性检查**: 价格不能超过 2 小时
2. ✅ **轮次验证**: 确保数据来自最新轮次
3. ✅ **正值检查**: 价格必须大于 0
4. ✅ **小数位转换**: 自动转换为 18 位小数标准

## 💡 使用示例

### 购买股票 ETF

```solidity
// 1. 授权 USDT
IERC20(usdt).approve(routerAddress, usdtAmount);

// 2. 使用 USDT 购买 ETF
uint256 shares = router.mintWithUSDT(
    usdtAmount,      // 支付的 USDT 数量
    minShares,       // 最少接收的份额（滑点保护）
    deadline         // 截止时间
);
```

### 赎回为 USDT

```solidity
// 1. 授权 ETF 份额
IERC20(etfCore).approve(routerAddress, shares);

// 2. 赎回为 USDT
uint256 usdtReceived = router.burnToUSDT(
    shares,
    minUSDT,
    deadline
);
```

### 查询 ETF 信息

```solidity
// 获取总价值（使用 Chainlink 实时价格）
uint256 totalValue = etfCore.getTotalValue();

// 获取份额价值
uint256 shareValue = etfCore.getShareValue();

// 查询资产列表
IStockETFCore.AssetInfo[] memory assets = etfCore.getAssets();
```

## 🧪 测试覆盖

### ChainlinkPriceOracle 测试 (18 个测试)

- ✅ 设置单个价格数据源
- ✅ 批量设置价格数据源
- ✅ 获取价格（单个/批量）
- ✅ 计算资产价值
- ✅ 价格有效性验证
- ✅ 过期价格拒绝
- ✅ 负价格拒绝
- ✅ 权限控制
- ✅ USDT 固定价格 1.0

### StockETFIntegration 测试 (11 个测试)

- ✅ ETF 初始化
- ✅ 总价值计算（Chainlink 价格）
- ✅ 份额价值计算
- ✅ 铸造/赎回功能
- ✅ 价格更新影响
- ✅ 再平衡触发
- ✅ 管理费收取
- ✅ 多用户场景
- ✅ 预言机集成
- ✅ 暂停/恢复功能

## 📊 系统架构

```
┌─────────────┐
│   用户      │
│  (USDT)     │
└──────┬──────┘
       │
       ↓
┌─────────────────────┐
│  ETFRouterV1        │
│  (简化操作)          │
└──────┬──────────────┘
       │
       ↓
┌─────────────────────┐
│  StockETFCore       │
│  (ETF 管理)         │
└──────┬──────────────┘
       │
       ↓
┌──────────────────────┐
│ ChainlinkPriceOracle │
│ (价格获取)           │
└──────┬───────────────┘
       │
       ↓
┌──────────────────────────┐
│  Chainlink Price Feeds   │
│  (TSLA/USD, AAPL/USD...) │
└──────────────────────────┘
```

## 🔒 安全特性

### 1. Chainlink 价格安全
- ✅ 去中心化预言机网络
- ✅ 多节点数据聚合
- ✅ 价格时效性验证
- ✅ 异常价格检测

### 2. 合约安全
- ✅ ReentrancyGuard (防重入)
- ✅ Pausable (紧急暂停)
- ✅ Ownable (权限控制)
- ✅ 滑点保护
- ✅ 交易截止时间

### 3. 审计建议
- 建议在主网部署前进行专业审计
- 关注点：价格操纵、闪电贷攻击、权限管理

## 📖 完整文档

详细使用指南请参考: [docs/STOCK_ETF_GUIDE.md](./docs/STOCK_ETF_GUIDE.md)

包含内容：
- 完整购买/赎回流程
- 前端集成示例（ethers.js）
- 再平衡机制说明
- 费用结构详解
- 常见问题解答

## 🛠️ 开发工具

```bash
# 格式化代码
forge fmt

# 生成 gas 报告
forge test --gas-report

# 查看测试覆盖率
forge coverage

# 部署到本地测试网
anvil  # 启动本地节点
forge script script/DeployStockETF.s.sol --fork-url http://localhost:8545 --broadcast
```

## 📝 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**开始构建你的股票 ETF 投资组合吧！** 🚀