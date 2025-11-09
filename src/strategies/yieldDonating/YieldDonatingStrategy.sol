// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "@octant-core/core/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IAaveVault
 * @notice Interface for Aave's ERC-4626 ATokenVault
 * @dev Extends IERC4626 with Aave-specific deposit/withdraw variants
 */
interface IYieldSource is IERC4626 {
    /**
     * @notice Deposit pre-existing aTokens directly
     * @param assets Amount of aTokens to deposit
     * @param receiver Address to receive vault shares
     * @return shares Amount of shares minted
     */
    function depositATokens(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Withdraw as aTokens instead of underlying asset
     * @param assets Amount of underlying assets to withdraw
     * @param receiver Address to receive aTokens
     * @param owner Owner of the shares being burned
     * @return shares Amount of shares burned
     */
    function withdrawATokens(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @notice Get the underlying aToken address
     * @return Address of the Aave aToken (e.g., aUSDC)
     */
    function aToken() external view returns (address);

    /**
     * @notice Get claimable vault manager fees
     * @return Amount of fees accumulated
     */
    function getClaimableFees() external view returns (uint256);
}

/**
 * @title YieldDonating Strategy Template
 * @author Octant
 * @notice Template for creating YieldDonating strategies that mint profits to donationAddress
 * @dev This strategy template works with the TokenizedStrategy pattern where
 *      initialization and management functions are handled by a separate contract.
 *      The strategy focuses on the core yield generation logic.
 *
 *      NOTE: To implement permissioned functions you can use the onlyManagement,
 *      onlyEmergencyAuthorized and onlyKeepers modifiers
 */
contract YieldDonatingStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    /// @notice Address of the yield source (e.g., Aave pool, Compound, Yearn vault)
    IYieldSource public immutable YIELD_SOURCE;

    /**
     * @param _asset Address of the underlying asset
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _yieldSource,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        YIELD_SOURCE = IYieldSource(_yieldSource);

        // Approve yield source to pull assets during deposits
        ERC20(_asset).forceApprove(_yieldSource, type(uint256).max);
        
        // Approve yield source to burn our vault shares during withdrawals
        // This is needed because ERC4626 vaults check allowance even when owner == msg.sender
        // in some implementations (like ATokenVault)
        ERC20(_yieldSource).forceApprove(_yieldSource, type(uint256).max);

        // TokenizedStrategy initialization will be handled separately
        // This is just a template - the actual initialization depends on
        // the specific TokenizedStrategy implementation being used
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deploy.
     */
    function _deployFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Deposit underlying to ATokenVault → receive vault shares
        // ATokenVault handles Aave v3 supply() call internally
        IYieldSource(address(YIELD_SOURCE)).deposit(_amount, address(this));
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Withdraw underlying from ATokenVault
        // Burns our vault shares, returns underlying to strategy
        IYieldSource(address(YIELD_SOURCE)).withdraw(
            _amount,
            address(this), // receiver of underlying
            address(this) // owner of shares being burned
        );
    }

    /**
     * @notice Report total assets held by strategy
     * @return _totalAssets Total underlying value (idle + deployed with yield)
     * @dev Trusted function called by keeper/management
     *      Must return accurate asset accounting for profit/loss calculation
     *
     * ACCOUNTING COMPONENTS:
     * 1. Idle: asset.balanceOf(address(this))
     * 2. Vault Shares: yieldSource.balanceOf(address(this))
     * 3. Deployed Value: yieldSource.convertToAssets(shares)
     * 4. Total: idle + deployed
     *
     * PROFIT/LOSS HANDLING (automatic by BaseStrategy):
     * - If _totalAssets > lastReportedAssets → PROFIT detected
     *   → BaseStrategy mints shares to donationAddress (dragonRouter)
     *   → User PPS remains unchanged (dilution offset by assets)
     *
     * - If _totalAssets < lastReportedAssets → LOSS detected
     *   → If enableBurning=true: Burns shares from donationAddress
     *   → User PPS unchanged until donation buffer exhausted
     *   → If enableBurning=false: Loss impacts all holders proportionally
     *
     * YIELD SOURCE:
     * - No reward tokens to claim (unlike Curve, Convex, etc.)
     * - Aave lending APY accrues in ATokenVault exchange rate
     * - convertToAssets() increases over time as yield accrues
     * - No harvesting or swapping required
     *
     * POST-SHUTDOWN BEHAVIOR:
     * - Can still be called after shutdown
     * - Check TokenizedStrategy.isShutdown() if redeployment logic exists
     * - For this strategy: no redeployment, purely accounting
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // TODO: Implement harvesting logic
        // 1. Amount of assets claimable from the yield source
        // 2. Amount of assets idle in the strategy
        // 3. Return the total (assets claimable + assets idle)

        // Idle assets sitting in strategy contract
        uint256 idle = asset.balanceOf(address(this));

        // Vault shares held by this strategy
        uint256 vaultShares = IYieldSource(address(YIELD_SOURCE)).balanceOf(address(this));

        // Convert vault shares to underlying value (includes accrued yield)
        uint256 deployed = IYieldSource(address(YIELD_SOURCE)).convertToAssets(vaultShares);

        // Return total assets under management
        _totalAssets = idle + deployed;

        // BaseStrategy compares _totalAssets with previous report
        // Automatically handles profit minting / loss burning
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get maximum withdrawal limit based on Aave liquidity
     * @return Maximum assets that can be withdrawn
     * @dev Mirrors ATokenVault's maxWithdraw which checks:
     *      - Aave v3 available liquidity (totalLiquidity - borrowed)
     *      - Reserve active/paused status
     *      - Strategy's deployed position
     *
     * USAGE:
     * - Called by TokenizedStrategy before withdraw
     * - Prevents revert on illiquid withdrawals
     * - Returns 0 if Aave pool is fully utilized
     *
     * IMPLEMENTATION NOTE:
     * - Does not include idle assets (handled separately)
     * - Represents only what can be freed from yield source
     */
    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return IYieldSource(address(YIELD_SOURCE)).maxWithdraw(address(this));
    }

    /**
     * @notice Get maximum deposit limit based on Aave constraints
     * @return Maximum assets that can be deposited
     * @dev Mirrors ATokenVault's maxDeposit which checks:
     *      - Aave v3 supply cap per asset
     *      - Reserve active/paused status
     *      - Vault-specific limits (if any)
     *
     * USAGE:
     * - Called by TokenizedStrategy before deposit
     * - Prevents revert by pre-checking limits
     * - Updates as Aave state changes
     */
    function availableDepositLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return IYieldSource(address(YIELD_SOURCE)).maxDeposit(address(this));
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal virtual override {}

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view virtual override returns (bool) {
        return false;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * USAGE SCENARIO:
     * 1. emergencyAdmin calls shutdownStrategy()
     * 2. emergencyAdmin calls emergencyWithdraw() to free funds
     * 3. Management calls report() to realize any profit/loss
     *
     * IMPLEMENTATION NOTE:
     * - _amount may exceed deployed balance (withdraw what's possible)
     * - Check isShutdown() in _harvestAndReport to prevent redeployment
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Force withdrawal from ATokenVault
        // May revert if Aave liquidity insufficient
        IYieldSource(address(YIELD_SOURCE)).withdraw(_amount, address(this), address(this));
    }
}
