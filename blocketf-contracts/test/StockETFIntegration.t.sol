// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BlockETFCore.sol";
import "../src/oracles/ChainlinkPriceOracle.sol";
import "../src/router/ETFRouterV1.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title StockETFIntegrationTest
 * @notice 完整的股票 ETF 系统集成测试（含 Chainlink）
 */
contract StockETFIntegrationTest is Test {
    StockETFCore public etfCore;
    ChainlinkPriceOracle public oracle;
    ETFRouterV1 public router;

    MockERC20 public usdt;
    MockERC20 public tsla;
    MockERC20 public aapl;
    MockERC20 public googl;
    MockERC20 public msft;
    MockERC20 public wbnb;

    MockAggregator public tslaFeed;
    MockAggregator public aaplFeed;
    MockAggregator public googlFeed;
    MockAggregator public msftFeed;

    address public owner;
    address public user1;
    address public user2;

    // Mock 路由器地址
    address public mockSwapRouter;
    address public mockQuoter;
    address public mockV2Router;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        mockSwapRouter = makeAddr("swapRouter");
        mockQuoter = makeAddr("quoter");
        mockV2Router = makeAddr("v2Router");

        // 1. 部署代币
        usdt = new MockERC20("Tether USD", "USDT", 18);
        tsla = new MockERC20("Tesla Token", "TSLA", 18);
        aapl = new MockERC20("Apple Token", "AAPL", 18);
        googl = new MockERC20("Google Token", "GOOGL", 18);
        msft = new MockERC20("Microsoft Token", "MSFT", 18);
        wbnb = new MockERC20("Wrapped BNB", "WBNB", 18);

        // 2. 创建 mock 价格数据源
        tslaFeed = new MockAggregator(8);
        aaplFeed = new MockAggregator(8);
        googlFeed = new MockAggregator(8);
        msftFeed = new MockAggregator(8);

        // 设置股票价格（8 位小数）
        tslaFeed.updateAnswer(25000000000);  // $250.00
        aaplFeed.updateAnswer(18000000000);  // $180.00
        googlFeed.updateAnswer(14000000000); // $140.00
        msftFeed.updateAnswer(38000000000);  // $380.00

        // 3. 部署 Chainlink 价格预言机
        oracle = new ChainlinkPriceOracle(address(usdt));

        // 4. 配置价格数据源
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

        // 5. 部署 ETF Core
        etfCore = new StockETFCore("Tech Stock ETF", "TECH");

        // 6. 设置价格预言机
        etfCore.setPriceOracle(address(oracle));

        // 7. 配置费率
        etfCore.setFees(100, 200); // 1% 赎回费，2% 年化管理费

        // 8. 初始化 ETF
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

        // Mint 初始代币给 owner
        tsla.mint(owner, 100e18);
        aapl.mint(owner, 100e18);
        googl.mint(owner, 100e18);
        msft.mint(owner, 100e18);

        // 授权
        tsla.approve(address(etfCore), 100e18);
        aapl.approve(address(etfCore), 100e18);
        googl.approve(address(etfCore), 100e18);
        msft.approve(address(etfCore), 100e18);

        // 初始化 ETF（1000 份额 + 1000 最小流动性）
        etfCore.initialize(tokens, weights, initialAmounts, 1000e18 + 1000);

        // 9. 部署 Router
        router = new ETFRouterV1(
            address(etfCore),
            mockSwapRouter,
            mockQuoter,
            address(oracle),
            mockV2Router,
            address(usdt),
            address(wbnb)
        );
    }

    function testETFInitialization() public {
        // 验证 ETF 已初始化
        assertTrue(etfCore.initialized());

        // 验证总供应量（初始份额 + 最小流动性）
        uint256 totalSupply = etfCore.totalSupply();
        assertEq(totalSupply, 1000e18 + 1000);

        // 验证资产配置
        IStockETFCore.AssetInfo[] memory assets = etfCore.getAssets();
        assertEq(assets.length, 4);
    }

    function testGetTotalValue() public {
        // 计算期望总价值
        // 100 TSLA * $250 = $25,000
        // 100 AAPL * $180 = $18,000
        // 100 GOOGL * $140 = $14,000
        // 100 MSFT * $380 = $38,000
        // Total = $95,000

        uint256 totalValue = etfCore.getTotalValue();
        assertEq(totalValue, 95000e18);
    }

    function testGetShareValue() public {
        // 份额价值 = 总价值 / 总份额
        // $95,000 / 1000.001 ≈ $94.999...

        uint256 shareValue = etfCore.getShareValue();
        assertApproxEqRel(shareValue, 95e18, 0.01e18); // 1% 误差容忍度
    }

    function testMintExactShares() public {
        // 给 user1 mint 股票代币
        tsla.mint(user1, 10e18);
        aapl.mint(user1, 10e18);
        googl.mint(user1, 10e18);
        msft.mint(user1, 10e18);

        vm.startPrank(user1);

        // 计算需要的数量
        uint256[] memory amounts = etfCore.calculateRequiredAmounts(100e18);

        // 授权
        tsla.approve(address(etfCore), amounts[0]);
        aapl.approve(address(etfCore), amounts[1]);
        googl.approve(address(etfCore), amounts[2]);
        msft.approve(address(etfCore), amounts[3]);

        // 铸造 100 份额
        uint256[] memory usedAmounts = etfCore.mintExactShares(100e18, user1);

        // 验证份额
        uint256 balance = etfCore.balanceOf(user1);
        assertEq(balance, 100e18);

        // 验证使用的数量
        assertEq(usedAmounts.length, 4);

        vm.stopPrank();
    }

    function testBurnShares() public {
        // 给 user1 mint 一些 ETF 份额
        tsla.mint(user1, 10e18);
        aapl.mint(user1, 10e18);
        googl.mint(user1, 10e18);
        msft.mint(user1, 10e18);

        vm.startPrank(user1);

        uint256[] memory amounts = etfCore.calculateRequiredAmounts(100e18);

        tsla.approve(address(etfCore), amounts[0]);
        aapl.approve(address(etfCore), amounts[1]);
        googl.approve(address(etfCore), amounts[2]);
        msft.approve(address(etfCore), amounts[3]);

        etfCore.mintExactShares(100e18, user1);

        // 赎回 50 份额
        uint256[] memory burnAmounts = etfCore.burn(50e18, user1);

        // 验证剩余份额（考虑 1% 赎回费）
        uint256 balance = etfCore.balanceOf(user1);
        assertEq(balance, 50e18);

        // 验证收到的代币数量
        assertEq(burnAmounts.length, 4);
        assertGt(burnAmounts[0], 0); // 收到了 TSLA
        assertGt(burnAmounts[1], 0); // 收到了 AAPL

        vm.stopPrank();
    }

    function testPriceUpdate() public {
        uint256 valueBefore = etfCore.getTotalValue();

        // 更新 TSLA 价格：$250 -> $300
        tslaFeed.updateAnswer(30000000000); // $300.00

        uint256 valueAfter = etfCore.getTotalValue();

        // 价值应该增加：50 * 100 = $5,000
        assertEq(valueAfter, valueBefore + 5000e18);
    }

    function testRebalanceInfo() public {
        // 更新价格，使权重失衡
        // TSLA: $250 -> $400 (增加 60%)
        tslaFeed.updateAnswer(40000000000);

        (
            uint256[] memory currentWeights,
            uint256[] memory targetWeights,
            bool needsRebalance
        ) = etfCore.getRebalanceInfo();

        // 应该需要再平衡（TSLA 权重增加超过 5%）
        assertTrue(needsRebalance);

        // TSLA 当前权重应该大于目标权重 25%
        assertGt(currentWeights[0], targetWeights[0]);
    }

    function testManagementFee() public {
        // 向前推进 1 年
        vm.warp(block.timestamp + 365 days);

        // 同时更新价格数据源的时间戳，避免 "Price too old" 错误
        tslaFeed.updateAnswer(25000000000);
        aaplFeed.updateAnswer(18000000000);
        googlFeed.updateAnswer(14000000000);
        msftFeed.updateAnswer(38000000000);

        // 收集管理费
        uint256 feeShares = etfCore.collectManagementFee();

        // 应该收到管理费份额（2% 年化）
        assertGt(feeShares, 0);
    }

    function testMultipleUsers() public {
        // User1 mint 100 份额
        tsla.mint(user1, 10e18);
        aapl.mint(user1, 10e18);
        googl.mint(user1, 10e18);
        msft.mint(user1, 10e18);

        vm.startPrank(user1);
        uint256[] memory amounts1 = etfCore.calculateRequiredAmounts(100e18);
        tsla.approve(address(etfCore), amounts1[0]);
        aapl.approve(address(etfCore), amounts1[1]);
        googl.approve(address(etfCore), amounts1[2]);
        msft.approve(address(etfCore), amounts1[3]);
        etfCore.mintExactShares(100e18, user1);
        vm.stopPrank();

        // User2 mint 200 份额
        tsla.mint(user2, 20e18);
        aapl.mint(user2, 20e18);
        googl.mint(user2, 20e18);
        msft.mint(user2, 20e18);

        vm.startPrank(user2);
        uint256[] memory amounts2 = etfCore.calculateRequiredAmounts(200e18);
        tsla.approve(address(etfCore), amounts2[0]);
        aapl.approve(address(etfCore), amounts2[1]);
        googl.approve(address(etfCore), amounts2[2]);
        msft.approve(address(etfCore), amounts2[3]);
        etfCore.mintExactShares(200e18, user2);
        vm.stopPrank();

        // 验证余额
        assertEq(etfCore.balanceOf(user1), 100e18);
        assertEq(etfCore.balanceOf(user2), 200e18);

        // 验证总供应量
        uint256 expectedTotal = 1000e18 + 1000 + 100e18 + 200e18;
        assertEq(etfCore.totalSupply(), expectedTotal);
    }

    function testOracleIntegration() public {
        // 测试预言机价格查询
        uint256 tslaPrice = oracle.getPrice(address(tsla));
        assertEq(tslaPrice, 250e18);

        uint256 aaplPrice = oracle.getPrice(address(aapl));
        assertEq(aaplPrice, 180e18);

        // 批量查询
        address[] memory tokens = new address[](4);
        tokens[0] = address(tsla);
        tokens[1] = address(aapl);
        tokens[2] = address(googl);
        tokens[3] = address(msft);

        uint256[] memory prices = oracle.getPrices(tokens);
        assertEq(prices.length, 4);
        assertEq(prices[0], 250e18);
        assertEq(prices[1], 180e18);
        assertEq(prices[2], 140e18);
        assertEq(prices[3], 380e18);
    }

    function testPauseAndUnpause() public {
        // 暂停 ETF
        etfCore.pause();
        assertTrue(etfCore.isPaused());

        // 尝试 mint 应该失败
        tsla.mint(user1, 10e18);
        vm.startPrank(user1);
        tsla.approve(address(etfCore), 10e18);

        vm.expectRevert();
        etfCore.mint(user1);

        vm.stopPrank();

        // 恢复 ETF
        etfCore.unpause();
        assertFalse(etfCore.isPaused());
    }
}

/**
 * @title MockERC20
 * @notice Mock ERC20 代币用于测试
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsValue
    ) ERC20(name, symbol) {
        _decimals = decimalsValue;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title MockAggregator
 * @notice Mock Chainlink 聚合器
 */
contract MockAggregator {
    int256 public answer;
    uint8 public decimals;
    uint256 public timestamp;
    uint80 public roundId;

    constructor(uint8 _decimals) {
        decimals = _decimals;
        timestamp = block.timestamp;
        roundId = 1;
    }

    function updateAnswer(int256 _answer) external {
        answer = _answer;
        timestamp = block.timestamp;
        roundId++;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 _roundId,
            int256 _answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (roundId, answer, timestamp, timestamp, roundId);
    }
}