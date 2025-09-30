// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title ChainlinkPriceOracle
 * @notice 使用 Chainlink 价格预言机获取股票类资产的实时价格
 * @dev 支持股票代币化资产（如 TSLA, AAPL, GOOGL 等）的价格获取
 */
contract ChainlinkPriceOracle is IPriceOracle, Ownable {
    // Chainlink price feeds for each token
    mapping(address => AggregatorV3Interface) public priceFeeds;

    // Cache for latest prices
    mapping(address => PriceInfo) private priceCache;

    // Staleness threshold - prices older than this are considered stale
    uint256 public stalenessThreshold = 1 hours;

    // Max price age for Chainlink data
    uint256 public maxPriceAge = 2 hours;

    // Base token (USDT) for price calculation
    address public immutable USDT;
    AggregatorV3Interface public usdtPriceFeed;

    constructor(address _usdt) Ownable(msg.sender) {
        USDT = _usdt;
    }

    /**
     * @notice 设置代币的 Chainlink 价格数据源
     * @param token 代币地址
     * @param feed Chainlink 聚合器地址
     * @dev 对于股票代币，使用对应的 Chainlink 股票价格数据源
     */
    function setPriceFeed(address token, address feed) external override onlyOwner {
        require(token != address(0), "Invalid token");
        require(feed != address(0), "Invalid feed");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

        // Verify feed is working by getting latest price
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        require(price > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale price");
        require(block.timestamp - updatedAt <= maxPriceAge, "Price too old");

        priceFeeds[token] = priceFeed;

        emit PriceFeedAdded(token, feed);
    }

    /**
     * @notice 批量设置价格数据源（节省 gas）
     */
    function setPriceFeedsBatch(
        address[] calldata tokens,
        address[] calldata feeds
    ) external onlyOwner {
        require(tokens.length == feeds.length, "Length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "Invalid token");
            require(feeds[i] != address(0), "Invalid feed");

            AggregatorV3Interface priceFeed = AggregatorV3Interface(feeds[i]);

            // Verify feed
            (
                uint80 roundId,
                int256 price,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = priceFeed.latestRoundData();

            require(price > 0, "Invalid price");
            require(answeredInRound >= roundId, "Stale price");
            require(block.timestamp - updatedAt <= maxPriceAge, "Price too old");

            priceFeeds[tokens[i]] = priceFeed;
            emit PriceFeedAdded(tokens[i], feeds[i]);
        }
    }

    /**
     * @notice 设置 USDT 的价格数据源
     * @param feed USDT/USD Chainlink 聚合器地址
     */
    function setUSDTPriceFeed(address feed) external onlyOwner {
        require(feed != address(0), "Invalid feed");
        usdtPriceFeed = AggregatorV3Interface(feed);
        emit PriceFeedAdded(USDT, feed);
    }

    /**
     * @notice 移除代币的价格数据源
     */
    function removePriceFeed(address token) external override onlyOwner {
        require(address(priceFeeds[token]) != address(0), "Feed not exists");
        delete priceFeeds[token];
        delete priceCache[token];
        emit PriceFeedRemoved(token);
    }

    /**
     * @notice 获取代币价格（18位小数，以USDT计价）
     * @param token 代币地址
     * @return price 代币价格
     */
    function getPrice(address token) external view override returns (uint256 price) {
        PriceInfo memory info = getPriceInfo(token);
        require(info.isValid, "Price not available");
        return info.price;
    }

    /**
     * @notice 批量获取代币价格
     */
    function getPrices(
        address[] calldata tokens
    ) external view override returns (uint256[] memory prices) {
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            PriceInfo memory info = getPriceInfo(tokens[i]);
            require(info.isValid, "Price not available");
            prices[i] = info.price;
        }
    }

    /**
     * @notice 获取代币完整价格信息
     * @param token 代币地址
     * @return 价格信息结构体
     */
    function getPriceInfo(address token) public view override returns (PriceInfo memory) {
        // Special case for USDT - always return 1.0
        if (token == USDT) {
            return PriceInfo({
                price: 1e18, // 1 USDT = 1 USD
                timestamp: block.timestamp,
                isValid: true
            });
        }

        AggregatorV3Interface feed = priceFeeds[token];
        require(address(feed) != address(0), "Price feed not set");

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        require(answer > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale price");
        require(block.timestamp - updatedAt <= maxPriceAge, "Price too old");

        uint256 price = uint256(answer);
        uint8 feedDecimals = feed.decimals();

        // Convert to 18 decimals (standard USD price format)
        if (feedDecimals < 18) {
            price = price * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            price = price / (10 ** (feedDecimals - 18));
        }

        // If we have USDT price feed, adjust for USDT price
        if (address(usdtPriceFeed) != address(0)) {
            (
                ,
                int256 usdtPrice,
                ,
                uint256 usdtUpdatedAt,

            ) = usdtPriceFeed.latestRoundData();

            require(usdtPrice > 0, "Invalid USDT price");
            require(block.timestamp - usdtUpdatedAt <= maxPriceAge, "USDT price too old");

            uint8 usdtDecimals = usdtPriceFeed.decimals();
            uint256 usdtPriceNormalized = uint256(usdtPrice);

            if (usdtDecimals < 18) {
                usdtPriceNormalized = usdtPriceNormalized * (10 ** (18 - usdtDecimals));
            } else if (usdtDecimals > 18) {
                usdtPriceNormalized = usdtPriceNormalized / (10 ** (usdtDecimals - 18));
            }

            // Adjust price to USDT terms: price_in_usdt = price_in_usd / usdt_price
            price = (price * 1e18) / usdtPriceNormalized;
        }

        return PriceInfo({
            price: price,
            timestamp: updatedAt,
            isValid: true
        });
    }

    /**
     * @notice 计算代币价值（USD）
     * @param token 代币地址
     * @param amount 代币数量
     * @return value 价值（18位小数）
     */
    function calculateValue(
        address token,
        uint256 amount
    ) external view override returns (uint256 value) {
        PriceInfo memory info = getPriceInfo(token);
        require(info.isValid, "Price not available");

        uint8 decimals = IERC20Metadata(token).decimals();

        // value = amount * price / 10^decimals
        value = (amount * info.price) / (10 ** decimals);
    }

    /**
     * @notice 计算多个代币的总价值
     */
    function calculateTotalValue(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external view override returns (uint256 totalValue) {
        require(tokens.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            PriceInfo memory info = getPriceInfo(tokens[i]);
            require(info.isValid, "Price not available");

            uint8 decimals = IERC20Metadata(tokens[i]).decimals();
            uint256 value = (amounts[i] * info.price) / (10 ** decimals);
            totalValue += value;
        }
    }

    /**
     * @notice 手动更新价格缓存（通常不需要，因为使用实时数据）
     */
    function updatePrice(address token) external override {
        PriceInfo memory info = getPriceInfo(token);
        priceCache[token] = info;
        emit PriceUpdated(token, info.price, info.timestamp);
    }

    /**
     * @notice 批量更新价格缓存
     */
    function updatePrices(address[] calldata tokens) external override {
        for (uint256 i = 0; i < tokens.length; i++) {
            PriceInfo memory info = getPriceInfo(tokens[i]);
            priceCache[tokens[i]] = info;
            emit PriceUpdated(tokens[i], info.price, info.timestamp);
        }
    }

    /**
     * @notice 检查价格是否有效
     */
    function isPriceValid(address token) external view override returns (bool) {
        if (token == USDT) return true;

        AggregatorV3Interface feed = priceFeeds[token];
        if (address(feed) == address(0)) return false;

        try feed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            return answer > 0
                && answeredInRound >= roundId
                && block.timestamp - updatedAt <= maxPriceAge;
        } catch {
            return false;
        }
    }

    /**
     * @notice 获取价格最后更新时间
     */
    function getLastUpdateTime(address token) external view override returns (uint256) {
        if (token == USDT) return block.timestamp;

        AggregatorV3Interface feed = priceFeeds[token];
        require(address(feed) != address(0), "Price feed not set");

        (, , , uint256 updatedAt, ) = feed.latestRoundData();
        return updatedAt;
    }

    /**
     * @notice 获取价格过期阈值
     */
    function getStalenessThreshold() external view override returns (uint256) {
        return stalenessThreshold;
    }

    /**
     * @notice 设置价格过期阈值
     */
    function setStalenessThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0, "Invalid threshold");
        stalenessThreshold = _threshold;
    }

    /**
     * @notice 设置 Chainlink 价格最大年龄
     */
    function setMaxPriceAge(uint256 _maxAge) external onlyOwner {
        require(_maxAge > 0, "Invalid max age");
        maxPriceAge = _maxAge;
    }

    /**
     * @notice 获取价格数据源地址
     */
    function getPriceFeed(address token) external view returns (address) {
        return address(priceFeeds[token]);
    }
}