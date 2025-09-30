// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IETFRouterV1.sol";
import "../interfaces/IStockETFCore.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IQuoterV2.sol";
import "../interfaces/IPancakeV3Pool.sol";
import "../interfaces/IPancakeV2Router.sol";
import "../interfaces/IPriceOracle.sol";

contract ETFRouterV1 is IETFRouterV1, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant SLIPPAGE_BASE = 10000;
    uint256 private constant MAX_SLIPPAGE = 500; // 5% max slippage

    // PancakeSwap V3 fee tiers
    uint24 private constant FEE_LOW = 500; // 0.05%
    uint24 private constant FEE_MEDIUM = 2500; // 0.25%
    uint24 private constant FEE_HIGH = 10000; // 1%

    // Core contracts
    IStockETFCore public immutable etfCore;
    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoter;
    IPriceOracle public immutable priceOracle;
    IPancakeV2Router public immutable v2Router;

    // Token addresses (BSC Mainnet - update for your network)
    address public immutable USDT;
    address public immutable WBNB;

    // Configuration
    uint256 public defaultSlippage = 300; // 3% default slippage
    uint24 public defaultPoolFee = FEE_MEDIUM; // Default to 0.25% fee pools

    // Pool addresses for direct USDT swaps (asset => pool)
    mapping(address => address) public assetPools;

    // Events for pool configuration
    event PoolSet(address indexed asset, address indexed pool);

    constructor(
        address _etfCore,
        address _swapRouter,
        address _quoter,
        address _priceOracle,
        address _v2Router,
        address _usdt,
        address _wbnb
    ) Ownable(msg.sender) {
        etfCore = IStockETFCore(_etfCore);
        swapRouter = ISwapRouter(_swapRouter);
        quoter = IQuoterV2(_quoter);
        priceOracle = IPriceOracle(_priceOracle);
        v2Router = IPancakeV2Router(_v2Router);
        USDT = _usdt;
        WBNB = _wbnb;
    }

    /**
     * @notice Get ETF assets from core contract
     */
    function _getETFAssets() private view returns (address[] memory) {
        IStockETFCore.AssetInfo[] memory assets = etfCore.getAssets();
        address[] memory tokens = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            tokens[i] = assets[i].token;
        }
        return tokens;
    }

    /**
     * @notice Get pool and fee for asset-USDT pair
     * @param asset The asset to swap with USDT
     * @return pool Pool address (zero if not configured)
     * @return fee Pool fee tier
     */
    function _getAssetPool(address asset) private view returns (address pool, uint24 fee) {
        pool = assetPools[asset];
        if (pool != address(0)) {
            // Get fee from the pool contract
            fee = IPancakeV3Pool(pool).fee();
        } else {
            // No pool configured, use default
            fee = defaultPoolFee;
        }
    }

    /**
     * @notice Mint ETF shares using USDT
     * @param usdtAmount Amount of USDT to spend
     * @param minShares Minimum shares to receive (slippage protection)
     * @param deadline Transaction deadline
     */
    function mintWithUSDT(
        uint256 usdtAmount,
        uint256 minShares,
        uint256 deadline
    ) external override whenNotPaused nonReentrant returns (uint256 shares) {
        require(Stock.timestamp <= deadline, "Router: EXPIRED");
        require(usdtAmount > 0, "Router: ZERO_AMOUNT");

        // Transfer USDT from user
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), usdtAmount);

        // Calculate required amounts for each asset
        uint256 estimatedShares = estimateSharesFromUSDT(usdtAmount);
        require(estimatedShares >= minShares, "Router: INSUFFICIENT_OUTPUT");

        uint256[] memory requiredAmounts = etfCore.calculateRequiredAmounts(estimatedShares);
        address[] memory etfAssets = _getETFAssets();

        // Swap USDT to each ETF asset
        for (uint256 i = 0; i < etfAssets.length; i++) {
            address asset = etfAssets[i];
            uint256 requiredAmount = requiredAmounts[i];

            if (asset == USDT) {
                // No swap needed for USDT
                continue;
            }

            // Calculate USDT needed for this asset
            uint256 usdtForAsset = _estimateUSDTForAsset(asset, requiredAmount);

            // Perform swap with slippage protection
            _swapUSDTForAsset(asset, usdtForAsset, requiredAmount, deadline);
        }

        // Approve ETF core to spend assets
        for (uint256 i = 0; i < etfAssets.length; i++) {
            IERC20(etfAssets[i]).forceApprove(address(etfCore), requiredAmounts[i]);
        }

        // Mint ETF shares (mintExactShares returns amounts array, not shares)
        etfCore.mintExactShares(estimatedShares, msg.sender);
        shares = estimatedShares;

        // Refund any remaining USDT
        uint256 remainingUSDT = IERC20(USDT).balanceOf(address(this));
        if (remainingUSDT > 0) {
            IERC20(USDT).safeTransfer(msg.sender, remainingUSDT);
        }

        emit MintWithUSDT(msg.sender, usdtAmount, shares);
    }

    /**
     * @notice Burn ETF shares to receive USDT
     * @param shares Amount of ETF shares to burn
     * @param minUSDT Minimum USDT to receive (slippage protection)
     * @param deadline Transaction deadline
     */
    function burnToUSDT(
        uint256 shares,
        uint256 minUSDT,
        uint256 deadline
    ) external override whenNotPaused nonReentrant returns (uint256 usdtAmount) {
        require(Stock.timestamp <= deadline, "Router: EXPIRED");
        require(shares > 0, "Router: ZERO_SHARES");

        // Transfer ETF shares from user
        IERC20(address(etfCore)).safeTransferFrom(msg.sender, address(this), shares);

        // Burn shares to get underlying assets
        uint256[] memory receivedAmounts = etfCore.burn(shares, address(this));
        address[] memory etfAssets = _getETFAssets();

        // Swap all assets to USDT
        for (uint256 i = 0; i < etfAssets.length; i++) {
            address asset = etfAssets[i];
            uint256 amount = receivedAmounts[i];

            if (asset == USDT || amount == 0) {
                continue; // Skip USDT and zero amounts
            }

            // Swap asset to USDT
            _swapAssetToUSDT(asset, amount, deadline);
        }

        // Get total USDT received
        usdtAmount = IERC20(USDT).balanceOf(address(this));
        require(usdtAmount >= minUSDT, "Router: INSUFFICIENT_OUTPUT");

        // Transfer USDT to user
        IERC20(USDT).safeTransfer(msg.sender, usdtAmount);

        emit BurnToUSDT(msg.sender, shares, usdtAmount);
    }

    /**
     * @notice Swap USDT for a specific ETF asset using configured pools
     */
    function _swapUSDTForAsset(
        address asset,
        uint256 usdtAmount,
        uint256 minAssetAmount,
        uint256 deadline
    ) private returns (uint256 amountOut) {
        // Apply slippage tolerance
        uint256 minAmountWithSlippage = (minAssetAmount * (SLIPPAGE_BASE - defaultSlippage)) / SLIPPAGE_BASE;

        if (asset == WBNB) {
            // Special case: use V2 for WBNB (no USDT/WBNB pool in V3)
            amountOut = _swapUSDTForWBNBV2(usdtAmount, minAmountWithSlippage, deadline);
        } else {
            // Regular V3 handling for other assets
            IERC20(USDT).forceApprove(address(swapRouter), usdtAmount);

            // Get configured pool for this asset
            (address pool, uint24 fee) = _getAssetPool(asset);

            if (pool != address(0)) {
                // Use configured pool for direct swap
                amountOut = swapRouter.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: USDT,
                        tokenOut: asset,
                        fee: fee,
                        recipient: address(this),
                        deadline: deadline,
                        amountIn: usdtAmount,
                        amountOutMinimum: minAmountWithSlippage,
                        sqrtPriceLimitX96: 0
                    })
                );
            } else {
                // Use direct swap with default fee
                amountOut = swapRouter.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: USDT,
                        tokenOut: asset,
                        fee: defaultPoolFee,
                        recipient: address(this),
                        deadline: deadline,
                        amountIn: usdtAmount,
                        amountOutMinimum: minAmountWithSlippage,
                        sqrtPriceLimitX96: 0
                    })
                );
            }
        }
    }

    /**
     * @notice Swap an ETF asset back to USDT using configured pools
     */
    function _swapAssetToUSDT(
        address asset,
        uint256 assetAmount,
        uint256 deadline
    ) private returns (uint256 amountOut) {
        if (asset == WBNB) {
            // Special case: use V2 for WBNB (no USDT/WBNB pool in V3)
            amountOut = _swapWBNBToUSDTV2(assetAmount, deadline);
        } else {
            // Regular V3 handling for other assets
            IERC20(asset).forceApprove(address(swapRouter), assetAmount);

            // Get configured pool for this asset
            (address pool, uint24 fee) = _getAssetPool(asset);

            if (pool != address(0)) {
                // Use configured pool for direct swap
                amountOut = swapRouter.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: asset,
                        tokenOut: USDT,
                        fee: fee,
                        recipient: address(this),
                        deadline: deadline,
                        amountIn: assetAmount,
                        amountOutMinimum: 0, // Accept any amount, check total at end
                        sqrtPriceLimitX96: 0
                    })
                );
            } else {
                // Use direct swap with default fee
                amountOut = swapRouter.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: asset,
                        tokenOut: USDT,
                        fee: defaultPoolFee,
                        recipient: address(this),
                        deadline: deadline,
                        amountIn: assetAmount,
                        amountOutMinimum: 0, // Accept any amount, check total at end
                        sqrtPriceLimitX96: 0
                    })
                );
            }
        }
    }

    /**
     * @notice Estimate USDT needed for a specific amount of asset
     */
    function _estimateUSDTForAsset(
        address asset,
        uint256 assetAmount
    ) private view returns (uint256) {
        if (asset == USDT) {
            return assetAmount;
        }

        // Use price oracle for estimation (quoter functions are not view)
        uint256 assetPrice = priceOracle.getPrice(asset);
        uint256 usdtPrice = priceOracle.getPrice(USDT);

        // Price oracle returns price in USD with 18 decimals
        uint256 usdtAmount = (assetAmount * assetPrice) / usdtPrice;

        // Add slippage buffer
        return (usdtAmount * (SLIPPAGE_BASE + defaultSlippage)) / SLIPPAGE_BASE;
    }

    /**
     * @notice Estimate USDT needed to mint specific shares
     */
    function estimateUSDTForMint(
        uint256 shares
    ) external view override returns (uint256 usdtNeeded) {
        uint256[] memory amounts = etfCore.calculateRequiredAmounts(shares);
        address[] memory etfAssets = _getETFAssets();

        for (uint256 i = 0; i < amounts.length; i++) {
            address asset = etfAssets[i];
            uint256 amount = amounts[i];

            if (asset == USDT) {
                usdtNeeded += amount;
            } else {
                usdtNeeded += _estimateUSDTForAsset(asset, amount);
            }
        }

        // Add overall slippage buffer
        usdtNeeded = (usdtNeeded * (SLIPPAGE_BASE + defaultSlippage)) / SLIPPAGE_BASE;
    }

    /**
     * @notice Estimate USDT received from burning shares
     */
    function estimateUSDTFromBurn(
        uint256 shares
    ) external view override returns (uint256 usdtAmount) {
        uint256[] memory amounts = etfCore.calculateBurnAmounts(shares);
        address[] memory etfAssets = _getETFAssets();

        for (uint256 i = 0; i < amounts.length; i++) {
            address asset = etfAssets[i];
            uint256 amount = amounts[i];

            if (asset == USDT) {
                usdtAmount += amount;
            } else {
                // Try to get quote from V3, fallback to oracle
                usdtAmount += _estimateUSDTFromAsset(asset, amount);
            }
        }

        // Deduct slippage
        usdtAmount = (usdtAmount * (SLIPPAGE_BASE - defaultSlippage)) / SLIPPAGE_BASE;
    }

    /**
     * @notice Estimate USDT received from selling an asset
     */
    function _estimateUSDTFromAsset(
        address asset,
        uint256 assetAmount
    ) private view returns (uint256) {
        if (asset == USDT) {
            return assetAmount;
        }

        // Use price oracle for estimation (quoter functions are not view)
        uint256 assetPrice = priceOracle.getPrice(asset);
        uint256 usdtPrice = priceOracle.getPrice(USDT);
        return (assetAmount * assetPrice) / usdtPrice;
    }

    /**
     * @notice Estimate shares that can be minted with USDT amount
     */
    function estimateSharesFromUSDT(
        uint256 usdtAmount
    ) public view override returns (uint256 shares) {
        // Get total value of ETF in USD
        uint256 totalValue = etfCore.getTotalValue();
        uint256 totalSupply = IERC20(address(etfCore)).totalSupply();

        if (totalSupply == 0 || totalValue == 0) {
            return 0;
        }

        // Calculate share value in USD
        uint256 shareValue = totalValue / totalSupply;

        // Convert USDT to USD value
        uint256 usdtPrice = priceOracle.getPrice(USDT);
        uint256 usdValue = (usdtAmount * usdtPrice) / 1e18;

        // Calculate shares (deduct slippage)
        uint256 effectiveValue = (usdValue * (SLIPPAGE_BASE - defaultSlippage)) / SLIPPAGE_BASE;
        shares = effectiveValue / shareValue;
    }

    /**
     * @notice Get the configured pool for an asset
     */
    function getAssetPool(address asset) external view returns (address pool, uint24 fee) {
        return _getAssetPool(asset);
    }

    // Admin functions
    function setDefaultSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= MAX_SLIPPAGE, "Router: SLIPPAGE_TOO_HIGH");
        defaultSlippage = _slippage;
    }

    function setDefaultPoolFee(uint24 _fee) external onlyOwner {
        require(
            _fee == FEE_LOW || _fee == FEE_MEDIUM || _fee == FEE_HIGH,
            "Router: INVALID_FEE"
        );
        defaultPoolFee = _fee;
    }

    /**
     * @notice Set pool address for a specific asset-USDT pair
     * @param asset The asset token address
     * @param pool The PancakeSwap V3 pool address for asset-USDT pair
     */
    function setAssetPool(address asset, address pool) external onlyOwner {
        require(asset != address(0), "Router: INVALID_ASSET");

        if (pool != address(0)) {
            // Validate that this is a valid V3 pool
            IPancakeV3Pool poolContract = IPancakeV3Pool(pool);
            address token0 = poolContract.token0();
            address token1 = poolContract.token1();

            // Ensure pool contains both asset and USDT
            require(
                (token0 == asset && token1 == USDT) || (token0 == USDT && token1 == asset),
                "Router: INVALID_POOL"
            );
        }

        assetPools[asset] = pool;
        emit PoolSet(asset, pool);
    }

    /**
     * @notice Set pool addresses for multiple assets in batch
     */
    function setAssetPoolsBatch(
        address[] calldata assets,
        address[] calldata pools
    ) external onlyOwner {
        require(assets.length == pools.length, "Router: ARRAY_LENGTH_MISMATCH");

        for (uint256 i = 0; i < assets.length; i++) {
            require(assets[i] != address(0), "Router: INVALID_ASSET");

            if (pools[i] != address(0)) {
                // Validate each pool
                IPancakeV3Pool poolContract = IPancakeV3Pool(pools[i]);
                address token0 = poolContract.token0();
                address token1 = poolContract.token1();

                require(
                    (token0 == assets[i] && token1 == USDT) || (token0 == USDT && token1 == assets[i]),
                    "Router: INVALID_POOL"
                );
            }

            assetPools[assets[i]] = pools[i];
            emit PoolSet(assets[i], pools[i]);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency function to recover stuck tokens
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @notice Swap USDT for WBNB using PancakeSwap V2
     */
    function _swapUSDTForWBNBV2(
        uint256 usdtAmount,
        uint256 minWBNBAmount,
        uint256 deadline
    ) private returns (uint256 amountOut) {
        IERC20(USDT).forceApprove(address(v2Router), usdtAmount);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WBNB;

        uint256[] memory amounts = v2Router.swapExactTokensForTokens(
            usdtAmount,
            minWBNBAmount,
            path,
            address(this),
            deadline
        );

        amountOut = amounts[1]; // WBNB amount
    }

    /**
     * @notice Swap WBNB for USDT using PancakeSwap V2
     */
    function _swapWBNBToUSDTV2(
        uint256 wbnbAmount,
        uint256 deadline
    ) private returns (uint256 amountOut) {
        IERC20(WBNB).forceApprove(address(v2Router), wbnbAmount);

        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = USDT;

        uint256[] memory amounts = v2Router.swapExactTokensForTokens(
            wbnbAmount,
            0, // Accept any amount, check total at end
            path,
            address(this),
            deadline
        );

        amountOut = amounts[1]; // USDT amount
    }
}