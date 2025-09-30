// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IStockETFCore.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IRebalanceCallback.sol";
import "./libraries/Errors.sol";

contract StockETFCore is
    IStockETFCore,
    ERC20,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    uint256 private constant WEIGHT_PRECISION = 10000;
    uint256 private constant FEE_PRECISION = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant MIN_MINT_AMOUNT = 1e15; // 0.001 shares
    uint256 private constant MINIMUM_LIQUIDITY = 1e3; // Permanently locked liquidity

    bool public initialized;
    address[] public assets;
    mapping(address => AssetInfo) public assetInfo;
    mapping(address => bool) public isAsset;

    FeeInfo public feeInfo;
    address public feeCollector;
    IPriceOracle public priceOracle;
    address public rebalancer;
    uint256 public rebalanceThreshold; // Basis points, e.g., 500 = 5%

    modifier onlyInitialized() {
        if (!initialized) revert Errors.NotInitialized();
        _;
    }

    modifier onlyRebalancer() {
        if (msg.sender != rebalancer && msg.sender != owner())
            revert Errors.Unauthorized();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        feeCollector = msg.sender;
        rebalanceThreshold = 500; // Default 5% deviation threshold
    }

    function initialize(
        address[] calldata _assets,
        uint32[] calldata _weights,
        uint256[] calldata _initialAmounts,
        uint256 _initialSupply
    ) external onlyOwner {
        if (initialized) revert Errors.AlreadyInitialized();
        if (_assets.length == 0) revert Errors.NoAssets();
        if (_assets.length != _weights.length) revert Errors.InvalidLength();
        if (_assets.length != _initialAmounts.length)
            revert Errors.InvalidLength();
        if (_initialSupply <= MINIMUM_LIQUIDITY)
            revert Errors.InsufficientInitialSupply();

        uint32 totalWeight;
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == address(0)) revert Errors.InvalidAsset();
            if (_weights[i] == 0) revert Errors.InvalidWeight();
            if (_initialAmounts[i] == 0) revert Errors.InvalidAmount();
            if (isAsset[_assets[i]]) revert Errors.DuplicateAsset();

            IERC20(_assets[i]).transferFrom(
                msg.sender,
                address(this),
                _initialAmounts[i]
            );

            assets.push(_assets[i]);
            assetInfo[_assets[i]] = AssetInfo({
                token: _assets[i],
                weight: _weights[i],
                reserve: uint224(_initialAmounts[i])
            });
            isAsset[_assets[i]] = true;
            totalWeight += _weights[i];
        }

        if (totalWeight != WEIGHT_PRECISION) revert Errors.InvalidTotalWeight();

        // Permanently lock the minimum liquidity by minting to address(1)
        // This prevents total supply from ever being 0 and provides better precision
        _mint(address(1), MINIMUM_LIQUIDITY);

        // Mint remaining initial supply to the caller
        _mint(msg.sender, _initialSupply - MINIMUM_LIQUIDITY);

        feeInfo.lastCollectTime = block.timestamp;
        initialized = true;

        emit AssetConfigured(_assets, _weights);
    }

    function mint(
        address to
    )
        external
        onlyInitialized
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (to == address(0)) revert Errors.InvalidRecipient();

        _collectManagementFee();

        uint256[] memory amounts = new uint256[](assets.length);
        uint256 minRatio = type(uint256).max;

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 balance = IERC20(asset).balanceOf(address(this));
            uint256 reserve = assetInfo[asset].reserve;

            if (balance <= reserve) revert Errors.NoNewAssets();
            amounts[i] = balance - reserve;

            if (reserve > 0) {
                uint256 ratio = (amounts[i] * 1e18) / reserve;
                if (ratio < minRatio) {
                    minRatio = ratio;
                }
            }
        }

        if (minRatio == type(uint256).max || minRatio == 0)
            revert Errors.InvalidRatio();

        uint256 totalSupplyBefore = totalSupply();
        shares = (totalSupplyBefore * minRatio) / 1e18;

        if (shares < MIN_MINT_AMOUNT) revert Errors.InsufficientMintAmount();

        _mint(to, shares);

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 actualAmount = (assetInfo[asset].reserve * minRatio) / 1e18;
            assetInfo[asset].reserve += uint224(actualAmount);
        }

        emit Mint(to, shares, amounts);
    }

    function mintExactShares(
        uint256 shares,
        address to
    )
        external
        onlyInitialized
        whenNotPaused
        nonReentrant
        returns (uint256[] memory amounts)
    {
        if (shares == 0) revert Errors.InvalidShares();
        if (to == address(0)) revert Errors.InvalidRecipient();
        if (shares < MIN_MINT_AMOUNT) revert Errors.InsufficientMintAmount();

        _collectManagementFee();

        uint256 totalShares = shares;

        amounts = new uint256[](assets.length);
        uint256 totalSupplyBefore = totalSupply();

        for (uint256 i = 0; i < assets.length; i++) {
            amounts[i] =
                (assetInfo[assets[i]].reserve * totalShares) /
                totalSupplyBefore;
            if (amounts[i] == 0) revert Errors.ZeroAmount();
        }

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            IERC20(asset).transferFrom(msg.sender, address(this), amounts[i]);
            assetInfo[asset].reserve += uint224(amounts[i]);
        }

        _mint(to, shares);

        emit Mint(to, shares, amounts);
    }

    function burn(
        uint256 shares,
        address to
    )
        external
        onlyInitialized
        whenNotPaused
        nonReentrant
        returns (uint256[] memory amounts)
    {
        if (shares == 0) revert Errors.InvalidShares();
        if (to == address(0)) revert Errors.InvalidRecipient();
        if (balanceOf(msg.sender) < shares) revert Errors.InsufficientBalance();

        _collectManagementFee();

        uint256 withdrawFee = (shares * feeInfo.withdrawFee) / WEIGHT_PRECISION;
        uint256 sharesAfterFee = shares - withdrawFee;

        if (withdrawFee > 0) {
            _transfer(msg.sender, feeCollector, withdrawFee);
        }

        amounts = new uint256[](assets.length);
        uint256 totalSupplyBefore = totalSupply();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            amounts[i] =
                (assetInfo[asset].reserve * sharesAfterFee) /
                totalSupplyBefore;

            if (amounts[i] == 0) revert Errors.ZeroAmount();
            assetInfo[asset].reserve -= uint224(amounts[i]);

            IERC20(asset).transfer(to, amounts[i]);
        }

        _burn(msg.sender, sharesAfterFee);

        emit Burn(msg.sender, sharesAfterFee, amounts);
    }

    function configureAssets(
        address[] calldata tokens,
        uint32[] calldata weights
    ) external onlyOwner {
        if (tokens.length == 0) revert Errors.NoAssets();
        if (tokens.length != weights.length) revert Errors.InvalidLength();
        if (initialized && totalSupply() > 0)
            revert Errors.CannotReconfigureAfterInit();

        for (uint256 i = 0; i < assets.length; i++) {
            delete assetInfo[assets[i]];
            isAsset[assets[i]] = false;
        }
        delete assets;

        uint32 totalWeight;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert Errors.InvalidAsset();
            if (weights[i] == 0) revert Errors.InvalidWeight();
            if (isAsset[tokens[i]]) revert Errors.DuplicateAsset();

            assets.push(tokens[i]);
            assetInfo[tokens[i]] = AssetInfo({
                token: tokens[i],
                weight: weights[i],
                reserve: 0
            });
            isAsset[tokens[i]] = true;
            totalWeight += weights[i];
        }

        if (totalWeight != WEIGHT_PRECISION) revert Errors.InvalidTotalWeight();

        emit AssetConfigured(tokens, weights);
    }

    function flashRebalance(
        address receiver,
        bytes calldata data
    ) external onlyRebalancer onlyInitialized nonReentrant {
        if (address(priceOracle) == address(0)) revert Errors.OracleNotSet();
        if (rebalancer == address(0)) revert Errors.RebalanceNotImplemented();

        (
            uint256[] memory currentWeights,
            uint256[] memory targetWeights,
            bool needsRebalance
        ) = getRebalanceInfo();
        if (!needsRebalance) revert Errors.RebalanceNotNeeded();

        // Calculate rebalancing requirements using signed amounts
        int256[] memory rebalanceAmounts = new int256[](assets.length);
        uint256[] memory balancesBefore = new uint256[](assets.length);
        uint256 totalValueBefore = getTotalValue();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            balancesBefore[i] = IERC20(asset).balanceOf(address(this));

            uint256 price = priceOracle.getPrice(asset);
            if (price == 0) revert Errors.InvalidPrice();
            uint8 decimals = IERC20Metadata(asset).decimals();

            if (currentWeights[i] > targetWeights[i]) {
                // Asset is over-weighted, needs to be sold (positive amount)
                uint256 excess = currentWeights[i] - targetWeights[i];
                uint256 excessValue = (totalValueBefore * excess) /
                    WEIGHT_PRECISION;
                uint256 sellAmount = (excessValue * (10 ** decimals)) / price;

                // Safety: Don't sell more than 50% of any asset
                uint256 maxSell = balancesBefore[i] / 2;
                if (sellAmount > maxSell) {
                    sellAmount = maxSell;
                }

                rebalanceAmounts[i] = int256(sellAmount); // Positive = sell
            } else if (currentWeights[i] < targetWeights[i]) {
                // Asset is under-weighted, needs to be bought (negative amount)
                uint256 deficit = targetWeights[i] - currentWeights[i];
                uint256 deficitValue = (totalValueBefore * deficit) /
                    WEIGHT_PRECISION;
                uint256 buyAmount = (deficitValue * (10 ** decimals)) / price;

                rebalanceAmounts[i] = -int256(buyAmount); // Negative = buy
            }
            // If weights are equal, rebalanceAmounts[i] remains 0
        }

        // Transfer over-weighted assets to receiver (flash loan)
        for (uint256 i = 0; i < assets.length; i++) {
            if (rebalanceAmounts[i] > 0) {
                // Positive = sell
                uint256 sellAmount = uint256(rebalanceAmounts[i]);
                IERC20(assets[i]).transfer(receiver, sellAmount);
            }
        }

        // Call rebalancer callback to perform swaps
        IRebalanceCallback(receiver).rebalanceCallback(
            assets,
            rebalanceAmounts,
            data
        );

        // Verify balances after callback
        uint256[] memory balancesAfter = new uint256[](assets.length);
        uint256[] memory newWeights = new uint256[](assets.length);
        uint256 totalValueAfter = 0;

        // Calculate total value after for weight calculation
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            balancesAfter[i] = IERC20(asset).balanceOf(address(this));

            uint256 price = priceOracle.getPrice(asset);
            if (price == 0) revert Errors.InvalidPrice();
            uint8 decimals = IERC20Metadata(asset).decimals();
            uint256 assetValue = (balancesAfter[i] * price) / (10 ** decimals);
            totalValueAfter += assetValue;
        }

        // Validate results and calculate new weights
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            // Ensure we didn't lose too much value (allowing for fees/slippage)
            if (balancesAfter[i] < (balancesBefore[i] * 90) / 100) {
                // Max 10% loss per asset
                revert Errors.ExcessiveLoss();
            }

            // Calculate new weights
            if (totalValueAfter > 0) {
                uint256 price = priceOracle.getPrice(asset);
                uint8 decimals = IERC20Metadata(asset).decimals();
                uint256 assetValue = (balancesAfter[i] * price) /
                    (10 ** decimals);
                newWeights[i] =
                    (assetValue * WEIGHT_PRECISION) /
                    totalValueAfter;
            }

            // Validate: deviation should be reduced (allowing some tolerance)
            uint256 targetWeight = uint256(assetInfo[asset].weight);
            uint256 oldDeviation = currentWeights[i] > targetWeight
                ? currentWeights[i] - targetWeight
                : targetWeight - currentWeights[i];
            uint256 newDeviation = newWeights[i] > targetWeight
                ? newWeights[i] - targetWeight
                : targetWeight - newWeights[i];

            // Allow improvement or slight degradation for gas efficiency
            if (newDeviation > oldDeviation + 200) {
                // Allow 2% tolerance
                revert Errors.InvalidRebalance();
            }

            // Update reserves to new balances
            assetInfo[asset].reserve = uint224(balancesAfter[i]);
        }

        // Ensure total value didn't drop too much (max 5% total loss)
        if (totalValueAfter < (totalValueBefore * 95) / 100) {
            revert Errors.ExcessiveLoss();
        }

        emit Rebalanced(currentWeights, newWeights);
    }

    function setFees(
        uint32 _withdrawFee,
        uint256 _annualManagementFeeBps
    ) external onlyOwner {
        if (_withdrawFee > 1000) revert Errors.FeeTooHigh(); // Max 10%
        if (_annualManagementFeeBps > 500) revert Errors.FeeTooHigh(); // Max 5%

        feeInfo.withdrawFee = _withdrawFee;

        uint256 feeRatePerSecond = (_annualManagementFeeBps * FEE_PRECISION) /
            (WEIGHT_PRECISION * SECONDS_PER_YEAR);
        feeInfo.managementFeeRate = uint128(feeRatePerSecond);

        emit FeeUpdated(_withdrawFee, _annualManagementFeeBps);
    }

    function collectManagementFee() external returns (uint256) {
        return _collectManagementFee();
    }

    function _collectManagementFee() internal returns (uint256 feeShares) {
        if (
            feeInfo.managementFeeRate == 0 ||
            block.timestamp <= feeInfo.lastCollectTime
        ) {
            return 0;
        }

        uint256 elapsed = block.timestamp - feeInfo.lastCollectTime;
        uint256 totalValue = getTotalValue();

        if (totalValue > 0 && totalSupply() > 0) {
            uint256 feeValue = (totalValue *
                feeInfo.managementFeeRate *
                elapsed) / FEE_PRECISION;

            if (feeValue > 0) {
                feeShares =
                    (feeValue * totalSupply()) /
                    (totalValue - feeValue);

                if (feeShares > 0) {
                    _mint(feeCollector, feeShares);
                    feeInfo.accumulatedFee += feeValue;

                    emit ManagementFeeCollected(
                        feeCollector,
                        feeShares,
                        feeValue
                    );
                }
            }
        }

        feeInfo.lastCollectTime = block.timestamp;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        if (_feeCollector == address(0)) revert Errors.InvalidFeeCollector();
        feeCollector = _feeCollector;
    }

    function setPriceOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert Errors.InvalidOracle();
        priceOracle = IPriceOracle(_oracle);
        emit PriceOracleUpdated(_oracle);
    }

    function setRebalancer(address _rebalancer) external onlyOwner {
        rebalancer = _rebalancer;
        emit RebalancerUpdated(_rebalancer);
    }

    function setRebalanceThreshold(uint256 _threshold) external onlyOwner {
        if (_threshold > 2000) revert Errors.ThresholdTooHigh(); // Max 20%
        rebalanceThreshold = _threshold;
        emit RebalanceThresholdUpdated(_threshold);
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused();
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused();
    }

    function getAssets() external view returns (AssetInfo[] memory) {
        AssetInfo[] memory result = new AssetInfo[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            result[i] = assetInfo[assets[i]];
        }
        return result;
    }

    function getFeeInfo() external view returns (FeeInfo memory) {
        return feeInfo;
    }

    function getTotalValue() public view returns (uint256) {
        if (address(priceOracle) == address(0)) revert Errors.OracleNotSet();

        uint256 totalValue = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 reserve = assetInfo[asset].reserve;

            if (reserve > 0) {
                uint256 price = priceOracle.getPrice(asset);
                if (price == 0) revert Errors.InvalidPrice();

                uint8 decimals = IERC20Metadata(asset).decimals();

                // Calculate USD value: reserve * price / 10^decimals
                // Price is expected to be in USD with 18 decimals (1e18 = $1)
                uint256 assetValue = (reserve * price) / (10 ** decimals);
                totalValue += assetValue;
            }
        }

        return totalValue;
    }

    function getShareValue() external view returns (uint256) {
        uint256 supply = totalSupply();
        return (getTotalValue() * 1e18) / supply;
    }

    function calculateMintShares(
        uint256[] calldata amounts
    ) external view returns (uint256) {
        if (amounts.length != assets.length) revert Errors.InvalidLength();

        uint256 minRatio = type(uint256).max;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assetInfo[assets[i]].reserve > 0) {
                uint256 ratio = (amounts[i] * 1e18) /
                    assetInfo[assets[i]].reserve;
                if (ratio < minRatio) {
                    minRatio = ratio;
                }
            }
        }

        if (minRatio == type(uint256).max) return 0;

        uint256 shares = (totalSupply() * minRatio) / 1e18;

        return shares;
    }

    function calculateBurnAmounts(
        uint256 shares
    ) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](assets.length);

        if (shares == 0) {
            return amounts;
        }

        uint256 withdrawFee = (shares * feeInfo.withdrawFee) / WEIGHT_PRECISION;
        uint256 sharesAfterFee = shares - withdrawFee;

        for (uint256 i = 0; i < assets.length; i++) {
            amounts[i] =
                (assetInfo[assets[i]].reserve * sharesAfterFee) /
                totalSupply();
        }
    }

    function calculateRequiredAmounts(
        uint256 shares
    ) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](assets.length);

        if (shares == 0) return amounts;

        uint256 totalSupplyNow = totalSupply();

        for (uint256 i = 0; i < assets.length; i++) {
            amounts[i] =
                (assetInfo[assets[i]].reserve * shares) /
                totalSupplyNow;
        }
    }

    function getRebalanceInfo()
        public
        view
        returns (
            uint256[] memory currentWeights,
            uint256[] memory targetWeights,
            bool needsRebalance
        )
    {
        currentWeights = new uint256[](assets.length);
        targetWeights = new uint256[](assets.length);
        needsRebalance = false;

        if (address(priceOracle) == address(0)) {
            return (currentWeights, targetWeights, needsRebalance);
        }

        uint256 totalValue = getTotalValue();
        if (totalValue == 0) {
            return (currentWeights, targetWeights, needsRebalance);
        }

        // Calculate current weights and target weights
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            AssetInfo memory info = assetInfo[asset];

            // Target weight (from configuration)
            targetWeights[i] = uint256(info.weight);

            // Current weight (based on current value)
            if (info.reserve > 0) {
                uint256 price = priceOracle.getPrice(asset);
                if (price > 0) {
                    uint8 decimals = IERC20Metadata(asset).decimals();
                    uint256 assetValue = (info.reserve * price) /
                        (10 ** decimals);
                    currentWeights[i] =
                        (assetValue * WEIGHT_PRECISION) /
                        totalValue;
                }
            }

            // Check if rebalancing is needed (deviation >= threshold)
            uint256 deviation = currentWeights[i] > targetWeights[i]
                ? currentWeights[i] - targetWeights[i]
                : targetWeights[i] - currentWeights[i];

            if (deviation >= rebalanceThreshold) {
                needsRebalance = true;
            }
        }
    }

    function getAnnualManagementFee() external view returns (uint256) {
        return
            (feeInfo.managementFeeRate * SECONDS_PER_YEAR * WEIGHT_PRECISION) /
            FEE_PRECISION;
    }

    function isPaused() external view returns (bool) {
        return paused();
    }
}
