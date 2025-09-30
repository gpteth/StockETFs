// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockStockToken
 * @notice 测试网用的模拟股票代币
 * @dev 用于在测试网测试 ETF 功能，模拟 TSLA、AAPL 等股票代币
 */
contract MockStockToken is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsValue
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimalsValue;

        // Mint 初始供应量给部署者（用于测试）
        _mint(msg.sender, 1_000_000 * (10 ** decimalsValue));
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice 铸造代币（仅限所有者）
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice 销毁代币
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice 批量空投（测试用）
     */
    function airdrop(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }
}