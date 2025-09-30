// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IRebalanceCallback.sol";
import "../interfaces/IBlockETFCore.sol";
import "../interfaces/IPancakeRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ExampleRebalancer is IRebalanceCallback {
    IPancakeRouter public immutable router;
    address public immutable etf;

    constructor(address _router, address _etf) {
        router = IPancakeRouter(_router);
        etf = _etf;
    }

    function executeRebalance() external {
        // Call flash rebalance on ETF - amounts are calculated automatically
        bytes memory data = abi.encode(msg.sender);
        IBlockETFCore(etf).flashRebalance(address(this), data);
    }

    function rebalanceCallback(
        address[] calldata assets,
        int256[] calldata amounts,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == etf, "Only ETF can call");

        // Example rebalancing logic using signed amounts:
        // positive amount = sell this asset (we received it from ETF)
        // negative amount = buy this asset (absolute value)
        // zero = no action needed

        // First pass: Sell over-weighted assets for base currency (USDT)
        for (uint256 i = 0; i < assets.length; i++) {
            if (amounts[i] > 0) {
                // Positive = sell this asset
                address sellAsset = assets[i];
                uint256 sellAmount = uint256(amounts[i]);

                // Example: Sell asset for USDT through DEX
                // IERC20(sellAsset).approve(address(router), sellAmount);
                // address[] memory path = new address[](2);
                // path[0] = sellAsset;
                // path[1] = USDT;
                // router.swapExactTokensForTokens(
                //     sellAmount,
                //     0, // Accept any amount of USDT
                //     path,
                //     address(this),
                //     block.timestamp + 300
                // );

                // For demo, just keep the asset
            }
        }

        // Second pass: Buy under-weighted assets with USDT
        for (uint256 i = 0; i < assets.length; i++) {
            if (amounts[i] < 0) {
                // Negative = buy this asset
                address buyAsset = assets[i];
                uint256 buyAmount = uint256(-amounts[i]); // Convert to positive

                // Example: Buy asset with USDT
                // address[] memory path = new address[](2);
                // path[0] = USDT;
                // path[1] = buyAsset;
                // router.swapTokensForExactTokens(
                //     buyAmount,
                //     type(uint256).max, // Pay any amount of USDT
                //     path,
                //     address(this),
                //     block.timestamp + 300
                // );

                // For demo, simulate buying
            }
        }

        // Finally, transfer all assets back to ETF
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 balance = IERC20(asset).balanceOf(address(this));

            if (balance > 0) {
                IERC20(asset).transfer(etf, balance);
            }
        }

        // This design is much cleaner:
        // - Single array instead of two
        // - Clear semantic meaning (positive=sell, negative=buy)
        // - Easier to process in a loop
        // - More gas efficient
    }
}