# 🚀 BSC 测试网部署检查清单

## ✅ 部署前检查

### 1. 环境准备
- [ ] 已安装 Foundry (`forge --version`)
- [ ] 已获取测试网 BNB（至少 0.5 BNB）
- [ ] 已准备好测试私钥
- [ ] （可选）已获取 BSCScan API Key

### 2. 配置文件
- [ ] 已复制 `.env.bsc-testnet` 为 `.env`
- [ ] 已填写私钥到 `.env`
- [ ] 已填写 BSCScan API Key（如需验证）
- [ ] 已检查 `.gitignore` 包含 `.env`

### 3. 代码检查
- [ ] 所有测试通过 (`forge test`)
- [ ] 合约编译成功 (`forge build`)
- [ ] 无严重警告

---

## 🎯 快速部署命令

```bash
# 1. 加载环境变量
source .env

# 2. 检查余额（确保有足够的 BNB）
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $BSC_TESTNET_RPC

# 3. 部署（不验证，快速）
forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url $BSC_TESTNET_RPC \
  --broadcast \
  -vvvv

# 4. 部署（带验证，推荐）
forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url $BSC_TESTNET_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY \
  -vvvv
```

---

## 📋 部署后检查

### 1. 记录合约地址

从部署输出复制以下地址：

```
Mock Tokens:
TSLA:  _________________________
AAPL:  _________________________
GOOGL: _________________________
MSFT:  _________________________

Mock Chainlink Feeds:
TSLA/USD:  _____________________
AAPL/USD:  _____________________
GOOGL/USD: _____________________
MSFT/USD:  _____________________

Core Contracts:
ChainlinkPriceOracle: __________
StockETFCore:         __________
ETFRouterV1:          __________
```

### 2. 验证部署

```bash
# 设置变量（替换为你的地址）
export ETF_CORE=0x...
export ORACLE=0x...
export TSLA=0x...

# 检查 ETF 是否初始化
cast call $ETF_CORE "initialized()(bool)" --rpc-url $BSC_TESTNET_RPC

# 检查总价值
cast call $ETF_CORE "getTotalValue()(uint256)" --rpc-url $BSC_TESTNET_RPC

# 检查 TSLA 价格（应该是 250e18）
cast call $ORACLE "getPrice(address)(uint256)" $TSLA --rpc-url $BSC_TESTNET_RPC
```

### 3. BSCScan 验证

访问 https://testnet.bscscan.com 并搜索你的合约地址：

- [ ] 合约代码已验证（显示绿色勾）
- [ ] 可以读取合约状态
- [ ] 可以写入合约（连接钱包）

---

## 🧪 功能测试

### Test 1: Mint 股票代币

```bash
export MY_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)

# Mint 100 TSLA
cast send $TSLA "mint(address,uint256)" $MY_ADDRESS 100000000000000000000 \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 检查余额
cast call $TSLA "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $BSC_TESTNET_RPC
```

预期结果: ✅ 余额显示 100000000000000000000 (100 TSLA)

### Test 2: 更新价格

```bash
export TSLA_FEED=0x...  # Mock Chainlink 地址

# 更新 TSLA 价格为 $300
cast send $TSLA_FEED "updateAnswer(int256)" 30000000000 \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 验证新价格
cast call $ORACLE "getPrice(address)(uint256)" $TSLA --rpc-url $BSC_TESTNET_RPC
```

预期结果: ✅ 价格显示 300000000000000000000 ($300)

### Test 3: 购买 ETF

```bash
# 1. 授权代币
cast send $TSLA "approve(address,uint256)" $ETF_CORE 10000000000000000000 \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 2. 计算需要的数量
cast call $ETF_CORE "calculateRequiredAmounts(uint256)(uint256[])" 10000000000000000000 \
  --rpc-url $BSC_TESTNET_RPC

# 3. Mint ETF 份额
cast send $ETF_CORE "mintExactShares(uint256,address)" 10000000000000000000 $MY_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 4. 检查 ETF 余额
cast call $ETF_CORE "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $BSC_TESTNET_RPC
```

预期结果: ✅ ETF 余额显示 10000000000000000000 (10 shares)

### Test 4: 赎回 ETF

```bash
# 赎回 5 个 ETF
cast send $ETF_CORE "burn(uint256,address)" 5000000000000000000 $MY_ADDRESS \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY

# 检查剩余 ETF 余额
cast call $ETF_CORE "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $BSC_TESTNET_RPC
```

预期结果: ✅ 剩余 5 个 ETF，收到相应的股票代币

---

## 📊 部署统计

记录你的部署统计：

```
部署时间: ____________
Gas 使用: ____________
总成本:   ____________ BNB
区块号:   ____________
```

---

## 🔗 重要链接

保存这些链接以便后续使用：

- **BSCScan**: https://testnet.bscscan.com/address/[ETF_CORE_ADDRESS]
- **水龙头**: https://testnet.bnbchain.org/faucet-smart
- **PancakeSwap**: https://pancake.kiemtienonline360.com/ (测试网)

---

## ⚠️ 常见问题

### Q1: "insufficient funds for gas"
**A**: 从水龙头获取更多测试 BNB

### Q2: "nonce has already been used"
**A**: 等待几秒或使用 `--legacy` 标志

### Q3: 编译错误 "Stack too deep"
**A**: 已解决，foundry.toml 中设置了 `via_ir = true`

### Q4: 验证失败
**A**:
```bash
# 手动验证
forge verify-contract <ADDRESS> <CONTRACT> \
  --chain bsc-testnet \
  --etherscan-api-key $BSCSCAN_API_KEY
```

---

## ✅ 部署完成

恭喜！你已成功部署股票 ETF 到 BSC 测试网。

下一步：
- [ ] 测试所有功能
- [ ] 更新前端配置
- [ ] 邀请用户测试
- [ ] 收集反馈
- [ ] 准备主网部署

---

**需要帮助？** 查看 [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) 获取详细说明。