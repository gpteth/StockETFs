// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/oracles/ChainlinkPriceOracle.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title ChainlinkPriceOracleTest
 * @notice 测试 Chainlink 价格预言机集成
 */
contract ChainlinkPriceOracleTest is Test {
    ChainlinkPriceOracle public oracle;

    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    // Mock 股票代币
    address public mockTSLA;
    address public mockAAPL;

    // Mock Chainlink 聚合器
    MockAggregator public mockTSLAFeed;
    MockAggregator public mockAAPLFeed;

    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // 部署预言机
        oracle = new ChainlinkPriceOracle(USDT);

        // 创建 mock 代币
        mockTSLA = makeAddr("TSLA");
        mockAAPL = makeAddr("AAPL");

        // 创建 mock 价格数据源
        mockTSLAFeed = new MockAggregator(8); // 8 decimals
        mockAAPLFeed = new MockAggregator(8);

        // 设置初始价格
        mockTSLAFeed.updateAnswer(25000000000); // $250.00
        mockAAPLFeed.updateAnswer(18000000000); // $180.00
    }

    function testSetPriceFeed() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        address feed = oracle.getPriceFeed(mockTSLA);
        assertEq(feed, address(mockTSLAFeed));
    }

    function testSetPriceFeedsBatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = mockTSLA;
        tokens[1] = mockAAPL;

        address[] memory feeds = new address[](2);
        feeds[0] = address(mockTSLAFeed);
        feeds[1] = address(mockAAPLFeed);

        oracle.setPriceFeedsBatch(tokens, feeds);

        assertEq(oracle.getPriceFeed(mockTSLA), address(mockTSLAFeed));
        assertEq(oracle.getPriceFeed(mockAAPL), address(mockAAPLFeed));
    }

    function testGetPrice() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        uint256 price = oracle.getPrice(mockTSLA);

        // 期望价格：250.00 USD，转换为 18 位小数
        assertEq(price, 250e18);
    }

    function testGetUSDTPrice() public {
        // USDT 应该始终返回 1.0
        uint256 price = oracle.getPrice(USDT);
        assertEq(price, 1e18);
    }

    function testGetPriceInfo() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        ChainlinkPriceOracle.PriceInfo memory info = oracle.getPriceInfo(mockTSLA);

        assertEq(info.price, 250e18);
        assertTrue(info.isValid);
        assertGt(info.timestamp, 0);
    }

    function testGetPrices() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));
        oracle.setPriceFeed(mockAAPL, address(mockAAPLFeed));

        address[] memory tokens = new address[](2);
        tokens[0] = mockTSLA;
        tokens[1] = mockAAPL;

        uint256[] memory prices = oracle.getPrices(tokens);

        assertEq(prices.length, 2);
        assertEq(prices[0], 250e18); // TSLA
        assertEq(prices[1], 180e18); // AAPL
    }

    function testCalculateValue() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        // 假设 TSLA 代币有 18 位小数
        vm.mockCall(
            mockTSLA,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(18))
        );

        // 计算 10 个 TSLA 的价值
        uint256 value = oracle.calculateValue(mockTSLA, 10e18);

        // 期望：10 * $250 = $2500
        assertEq(value, 2500e18);
    }

    function testCalculateTotalValue() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));
        oracle.setPriceFeed(mockAAPL, address(mockAAPLFeed));

        // Mock decimals
        vm.mockCall(
            mockTSLA,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(18))
        );
        vm.mockCall(
            mockAAPL,
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(18))
        );

        address[] memory tokens = new address[](2);
        tokens[0] = mockTSLA;
        tokens[1] = mockAAPL;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18; // 10 TSLA
        amounts[1] = 20e18; // 20 AAPL

        uint256 totalValue = oracle.calculateTotalValue(tokens, amounts);

        // 期望：(10 * $250) + (20 * $180) = $2500 + $3600 = $6100
        assertEq(totalValue, 6100e18);
    }

    function testIsPriceValid() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        bool isValid = oracle.isPriceValid(mockTSLA);
        assertTrue(isValid);

        // 未设置的代币应该返回 false
        bool invalidToken = oracle.isPriceValid(makeAddr("INVALID"));
        assertFalse(invalidToken);
    }

    function testRevertOnStalePrice() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        // 模拟价格过期（向前推进 3 小时）
        vm.warp(block.timestamp + 3 hours);

        vm.expectRevert("Price too old");
        oracle.getPrice(mockTSLA);
    }

    function testRevertOnNegativePrice() public {
        mockTSLAFeed.updateAnswer(-100);

        vm.expectRevert("Invalid price");
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));
    }

    function testRemovePriceFeed() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        oracle.removePriceFeed(mockTSLA);

        address feed = oracle.getPriceFeed(mockTSLA);
        assertEq(feed, address(0));
    }

    function testOnlyOwnerCanSetPriceFeed() public {
        vm.prank(user);
        vm.expectRevert();
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));
    }

    function testUpdatePrice() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        oracle.updatePrice(mockTSLA);

        uint256 price = oracle.getPrice(mockTSLA);
        assertEq(price, 250e18);
    }

    function testUpdatePrices() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));
        oracle.setPriceFeed(mockAAPL, address(mockAAPLFeed));

        address[] memory tokens = new address[](2);
        tokens[0] = mockTSLA;
        tokens[1] = mockAAPL;

        oracle.updatePrices(tokens);

        uint256 tslaPrice = oracle.getPrice(mockTSLA);
        uint256 aaplPrice = oracle.getPrice(mockAAPL);

        assertEq(tslaPrice, 250e18);
        assertEq(aaplPrice, 180e18);
    }

    function testGetLastUpdateTime() public {
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));

        uint256 lastUpdate = oracle.getLastUpdateTime(mockTSLA);
        assertGt(lastUpdate, 0);
        assertLe(lastUpdate, block.timestamp);
    }

    function testSetStalenessThreshold() public {
        oracle.setStalenessThreshold(2 hours);

        uint256 threshold = oracle.getStalenessThreshold();
        assertEq(threshold, 2 hours);
    }

    function testSetMaxPriceAge() public {
        oracle.setMaxPriceAge(3 hours);

        // 验证通过尝试获取价格（不会因为 maxPriceAge 而失败）
        oracle.setPriceFeed(mockTSLA, address(mockTSLAFeed));
        uint256 price = oracle.getPrice(mockTSLA);
        assertGt(price, 0);
    }
}

/**
 * @title MockAggregator
 * @notice Mock Chainlink 聚合器用于测试
 */
contract MockAggregator is AggregatorV3Interface {
    int256 public answer;
    uint8 public override decimals;
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
        override
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

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        override
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