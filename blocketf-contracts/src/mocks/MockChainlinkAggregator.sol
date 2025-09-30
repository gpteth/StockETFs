// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockChainlinkAggregator
 * @notice 测试网用的模拟 Chainlink 价格聚合器
 * @dev 由于 BSC 测试网没有股票价格源，需要使用 Mock 合约模拟
 */
contract MockChainlinkAggregator is AggregatorV3Interface, Ownable {
    uint8 public override decimals;
    string public override description;
    uint256 public override version;

    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    RoundData private latestRound;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(
        uint8 _decimals,
        string memory _description,
        int256 _initialAnswer
    ) Ownable(msg.sender) {
        decimals = _decimals;
        description = _description;
        version = 1;

        // 设置初始价格
        latestRound = RoundData({
            roundId: 1,
            answer: _initialAnswer,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });
    }

    /**
     * @notice 更新价格（仅限所有者）
     * @param _answer 新价格
     */
    function updateAnswer(int256 _answer) external onlyOwner {
        require(_answer > 0, "Answer must be positive");

        latestRound.roundId++;
        latestRound.answer = _answer;
        latestRound.startedAt = block.timestamp;
        latestRound.updatedAt = block.timestamp;
        latestRound.answeredInRound = latestRound.roundId;

        emit AnswerUpdated(_answer, latestRound.roundId, block.timestamp);
    }

    /**
     * @notice 批量更新价格（模拟价格波动）
     */
    function updateAnswerWithTimestamp(
        int256 _answer,
        uint256 _timestamp
    ) external onlyOwner {
        require(_answer > 0, "Answer must be positive");
        require(_timestamp <= block.timestamp, "Future timestamp not allowed");

        latestRound.roundId++;
        latestRound.answer = _answer;
        latestRound.startedAt = _timestamp;
        latestRound.updatedAt = _timestamp;
        latestRound.answeredInRound = latestRound.roundId;

        emit AnswerUpdated(_answer, latestRound.roundId, _timestamp);
    }

    /**
     * @notice 获取最新轮次数据
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            latestRound.roundId,
            latestRound.answer,
            latestRound.startedAt,
            latestRound.updatedAt,
            latestRound.answeredInRound
        );
    }

    /**
     * @notice 获取指定轮次数据（简化实现，只返回最新数据）
     */
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        require(_roundId <= latestRound.roundId, "Round not complete");

        // 简化实现：只返回最新数据
        return (
            latestRound.roundId,
            latestRound.answer,
            latestRound.startedAt,
            latestRound.updatedAt,
            latestRound.answeredInRound
        );
    }

    /**
     * @notice 获取当前价格
     */
    function latestAnswer() external view returns (int256) {
        return latestRound.answer;
    }

    /**
     * @notice 获取当前轮次 ID
     */
    function latestRoundId() external view returns (uint80) {
        return latestRound.roundId;
    }
}