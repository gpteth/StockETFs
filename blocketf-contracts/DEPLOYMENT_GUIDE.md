# BSC 测试网部署指南

## 📋 前置要求

1. ✅ 安装 Foundry
2. ✅ 准备测试网 BNB（用于支付 gas）
3. ✅ 准备私钥
4. ✅ （可选）BSCScan API Key（用于验证合约）

## 🚰 获取测试网 BNB

访问 BSC 测试网水龙头获取免费的测试 BNB：

🔗 https://testnet.bnbchain.org/faucet-smart

每次可获得 0.5 BNB（足够部署和测试）

## ⚙️ 配置环境

### 1. 复制环境变量模板

```bash
cp .env.bsc-testnet .env
```

### 2. 编辑 .env 文件

```bash
vim .env
```

填入你的配置：

```bash
# 私钥（不要带 0x 前缀）
PRIVATE_KEY=your_private_key_here

# BSC 测试网 RPC（已配置好，通常不需要改）
BSC_TESTNET_RPC=https://data-seed-prebsc-1-s1.binance.org:8545/

# BSCScan API Key（可选，用于验证合约）
# 在 https://bscscan.com/myapikey 申请
BSCSCAN_API_KEY=your_api_key_here
```

**⚠️ 安全提示**:
- 永远不要提交 .env 文件到 Git
- 只在测试网使用测试私钥
- 主网部署前务必使用硬件钱包

## 🚀 部署步骤

### 方法 1: 一键部署（推荐）

```bash
# 加载环境变量
source .env

# 部署到测试网（带验证）
forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url $BSC_TESTNET_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY \
  -vvvv
```

### 方法 2: 不验证合约（快速测试）

```bash
forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url $BSC_TESTNET_RPC \
  --broadcast \
  -vvvv
```

## 📝 部署内容

脚本会自动部署以下合约：

### 1. Mock 合约（测试专用）
- ✅ **MockStockToken** x 4（TSLA, AAPL, GOOGL, MSFT）
- ✅ **MockChainlinkAggregator** x 4（价格预言机）

### 2. 核心合约
- ✅ **ChainlinkPriceOracle** - 价格预言机
- ✅ **StockETFCore** - ETF 核心合约
- ✅ **ETFRouterV1** - 路由合约

### 3. 自动配置
- ✅ 配置价格数据源
- ✅ 初始化 ETF（100 TSLA + 100 AAPL + 100 GOOGL + 100 MSFT）
- ✅ 设置费率（1% 赎回费，2% 年化管理费）

## 📊 部署后输出

部署成功后会看到类似输出：

```
========================================
Deployment Summary
========================================

Mock Tokens:
  TSLA: 0x1234...
  AAPL: 0x5678...
  GOOGL: 0x9abc...
  MSFT: 0xdef0...

Mock Chainlink Feeds:
  TSLA/USD: 0x1111...
  AAPL/USD: 0x2222...
  GOOGL/USD: 0x3333...
  MSFT/USD: 0x4444...

Core Contracts:
  ChainlinkPriceOracle: 0xaaaa...
  StockETFCore: 0xbbbb...
  ETFRouterV1: 0xcccc...

ETF Info:
  Total Value: 95000 USD
  Share Value: 95 USD
  Total Supply: 1000 shares

========================================
```

## 🧪 测试部署

### 1. 检查合约状态

```bash
# 设置合约地址（从部署输出复制）
export ETF_CORE=0x...
export ORACLE=0x...
export ROUTER=0x...

# 查询 ETF 总价值
cast call $ETF_CORE "getTotalValue()" --rpc-url $BSC_TESTNET_RPC

# 查询份额价值
cast call $ETF_CORE "getShareValue()" --rpc-url $BSC_TESTNET_RPC

# 查询 TSLA 价格
export TSLA=0x...  # 从部署输出复制
cast call $ORACLE "getPrice(address)(uint256)" $TSLA --rpc-url $BSC_TESTNET_RPC
```

### 2. Mint 测试代币给自己

```bash
# 设置你的地址
export MY_ADDRESS=0x...

# Mint 100 个 TSLA
cast send $TSLA "mint(address,uint256)" $MY_ADDRESS 100000000000000000000 \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 检查余额
cast call $TSLA "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $BSC_TESTNET_RPC
```

### 3. 测试购买 ETF

```bash
# 1. 授权股票代币
cast send $TSLA "approve(address,uint256)" $ETF_CORE 10000000000000000000 \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 对其他代币重复授权...

# 2. 计算需要的代币数量
cast call $ETF_CORE "calculateRequiredAmounts(uint256)(uint256[])" 10000000000000000000 \
  --rpc-url $BSC_TESTNET_RPC

# 3. 铸造 ETF 份额
cast send $ETF_CORE "mintExactShares(uint256,address)" 10000000000000000000 $MY_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 4. 查看 ETF 余额
cast call $ETF_CORE "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $BSC_TESTNET_RPC
```

### 4. 测试赎回 ETF

```bash
# 1. 赎回 5 个 ETF 份额
cast send $ETF_CORE "burn(uint256,address)" 5000000000000000000 $MY_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 2. 查看收到的股票代币
cast call $TSLA "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $BSC_TESTNET_RPC
```

## 🌐 在 BSCScan 上查看

所有部署的合约都可以在 BSCScan 测试网上查看：

🔗 https://testnet.bscscan.com

搜索你的合约地址即可查看：
- 合约代码（如果已验证）
- 交易历史
- 代币余额
- 调用合约功能

## 🔧 更新 Mock 价格

你可以更新 Mock Chainlink 聚合器的价格来测试价格变化：

```bash
export TSLA_FEED=0x...  # Mock Chainlink 聚合器地址

# 更新 TSLA 价格为 $300.00（8 位小数）
cast send $TSLA_FEED "updateAnswer(int256)" 30000000000 \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 验证新价格
cast call $ORACLE "getPrice(address)(uint256)" $TSLA --rpc-url $BSC_TESTNET_RPC
```

## 📱 前端集成

部署后，你可以使用以下信息集成前端：

```javascript
// 测试网配置
const NETWORK = {
  chainId: 97, // BSC 测试网
  rpcUrl: 'https://data-seed-prebsc-1-s1.binance.org:8545/',
  blockExplorer: 'https://testnet.bscscan.com'
};

// 合约地址（从部署输出复制）
const CONTRACTS = {
  etfCore: '0x...',
  oracle: '0x...',
  router: '0x...',
  tokens: {
    tsla: '0x...',
    aapl: '0x...',
    googl: '0x...',
    msft: '0x...'
  }
};

// 使用 ethers.js 连接
import { ethers } from 'ethers';

const provider = new ethers.JsonRpcProvider(NETWORK.rpcUrl);
const etfCore = new ethers.Contract(CONTRACTS.etfCore, ETF_ABI, provider);

// 查询 ETF 信息
const totalValue = await etfCore.getTotalValue();
const shareValue = await etfCore.getShareValue();
console.log('Total Value:', ethers.formatUnits(totalValue, 18), 'USD');
console.log('Share Value:', ethers.formatUnits(shareValue, 18), 'USD');
```

## 🐛 故障排查

### 问题 1: 余额不足
```
Error: insufficient funds for gas * price + value
```
**解决**: 从水龙头获取更多测试 BNB

### 问题 2: Nonce 错误
```
Error: nonce has already been used
```
**解决**: 等待几秒后重试，或清除交易历史

### 问题 3: 合约验证失败
```
Error: verification failed
```
**解决**:
- 检查 BSCSCAN_API_KEY 是否正确
- 重试验证: `forge verify-contract <ADDRESS> <CONTRACT> --chain bsc-testnet`

### 问题 4: RPC 超时
```
Error: request timeout
```
**解决**: 更换 RPC 端点：
- https://data-seed-prebsc-1-s2.binance.org:8545/
- https://data-seed-prebsc-2-s1.binance.org:8545/

## 📚 相关资源

- 📖 [BSC 测试网文档](https://docs.bnbchain.org/docs/bsc-testnet)
- 🚰 [测试网水龙头](https://testnet.bnbchain.org/faucet-smart)
- 🔍 [BSCScan 测试网](https://testnet.bscscan.com)
- 📝 [完整使用指南](./docs/STOCK_ETF_GUIDE.md)

## ✅ 下一步

部署成功后，你可以：

1. ✅ 在 BSCScan 上验证合约
2. ✅ 测试购买和赎回功能
3. ✅ 更新价格测试再平衡
4. ✅ 集成到你的前端应用
5. ✅ 邀请用户测试

---

**准备好了吗？开始部署吧！** 🚀

```bash
source .env && \
forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url $BSC_TESTNET_RPC \
  --broadcast \
  -vvvv
```