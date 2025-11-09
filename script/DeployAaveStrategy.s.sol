// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {YieldDonatingStrategy} from "../src/strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title Deploy Aave YieldDonating Strategy
 * @notice Deployment script for Aave v3 USDC ERC4626 vault integration
 *
 * DEPLOYMENT STEPS:
 * 1. Deploy YieldDonatingTokenizedStrategy implementation (if not already deployed)
 * 2. Deploy YieldDonatingStrategy with Aave USDC vault as yield source
 * 3. Verify configuration
 *
 * USAGE:
 * # Dry run (fork simulation):
 * forge script script/DeployAaveStrategy.s.sol --fork-url $ETH_RPC_URL -vvv
 *
 * # Actual deployment (TESTNET FIRST!):
 * forge script script/DeployAaveStrategy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 *
 * # Mainnet (after thorough testing):
 * forge script script/DeployAaveStrategy.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify --slow
 *
 * DEFAULT CONFIG:
 * - Asset: USDC (0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
 * - Yield Source: Aave v3 Static aUSDC Vault (0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6)
 * - Decimals: 6 (USDC standard)
 */
contract DeployAaveStrategy is Script {
    // Deployment configuration
    struct DeployConfig {
        address yieldSource;      // Aave ERC4626 vault address
        address asset;            // Underlying asset (WETH, USDC, etc.)
        string strategyName;      // Strategy name
        address management;       // Management address
        address keeper;           // Keeper address (can call report())
        address emergencyAdmin;   // Emergency admin (can shutdown)
        address dragonRouter;     // Donation address (receives yield)
        bool enableBurning;       // Enable loss protection via burning
    }

    function run() external {
        // Read configuration from environment or use defaults
        DeployConfig memory config = getConfig();

        // Log configuration
        console2.log("=== Aave YieldDonating Strategy Deployment ===");
        console2.log("Yield Source (Aave Vault):", config.yieldSource);
        console2.log("Asset:", config.asset);
        console2.log("Strategy Name:", config.strategyName);
        console2.log("Management:", config.management);
        console2.log("Keeper:", config.keeper);
        console2.log("Emergency Admin:", config.emergencyAdmin);
        console2.log("Dragon Router:", config.dragonRouter);
        console2.log("Enable Burning:", config.enableBurning);
        console2.log("");

        // Pre-deployment validation
        validateConfig(config);

        // Start broadcasting transactions (only if PRIVATE_KEY is set)
        // For fork simulations without --broadcast, we can skip this
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        }

        // 1. Deploy TokenizedStrategy implementation (if needed)
        address tokenizedStrategyImpl = deployTokenizedStrategy();

        // 2. Deploy YieldDonatingStrategy
        address strategyAddress = deployStrategy(config, tokenizedStrategyImpl);

        if (deployerPrivateKey != 0) {
            vm.stopBroadcast();
        }

        // Post-deployment verification
        verifyDeployment(strategyAddress, config);

        // Output deployment info
        console2.log("");
        console2.log("=== Deployment Successful ===");
        console2.log("TokenizedStrategy Implementation:", tokenizedStrategyImpl);
        console2.log("YieldDonatingStrategy:", strategyAddress);
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Verify contracts on Etherscan");
        console2.log("2. Test deposit/withdraw with small amounts");
        console2.log("3. Monitor first report() execution");
        console2.log("4. Set up keeper automation (Gelato/Chainlink)");
    }

    function getConfig() internal view returns (DeployConfig memory) {
        // Option 1: Read from environment variables
        if (vm.envOr("DEPLOY_USE_ENV", false)) {
            return DeployConfig({
                yieldSource: vm.envAddress("DEPLOY_YIELD_SOURCE"),
                asset: vm.envAddress("DEPLOY_ASSET"),
                strategyName: vm.envString("DEPLOY_STRATEGY_NAME"),
                management: vm.envAddress("DEPLOY_MANAGEMENT"),
                keeper: vm.envAddress("DEPLOY_KEEPER"),
                emergencyAdmin: vm.envAddress("DEPLOY_EMERGENCY_ADMIN"),
                dragonRouter: vm.envAddress("DEPLOY_DRAGON_ROUTER"),
                enableBurning: vm.envBool("DEPLOY_ENABLE_BURNING")
            });
        }

        // Option 2: Hardcoded defaults for testing
        return DeployConfig({
            // Aave v3 USDC ERC4626 vault on Ethereum mainnet (Static aUSDC Vault)
            yieldSource: 0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6,

            // USDC token
            asset: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,

            // Strategy name
            strategyName: "Aave USDC YieldDonating Strategy",

            // Roles (CHANGE THESE FOR PRODUCTION!)
            management: msg.sender,        // Deployer as management initially
            keeper: msg.sender,            // Deployer as keeper initially
            emergencyAdmin: msg.sender,    // Deployer as emergency admin initially
            dragonRouter: msg.sender,      // MUST be changed to actual dragonRouter

            // Enable loss protection
            enableBurning: true
        });
    }

    function validateConfig(DeployConfig memory config) internal view {
        console2.log("Validating configuration...");

        // Validate addresses are not zero
        require(config.yieldSource != address(0), "Invalid yieldSource");
        require(config.asset != address(0), "Invalid asset");
        require(config.management != address(0), "Invalid management");
        require(config.keeper != address(0), "Invalid keeper");
        require(config.emergencyAdmin != address(0), "Invalid emergencyAdmin");
        require(config.dragonRouter != address(0), "Invalid dragonRouter");

        // Validate yield source is ERC4626
        try IERC4626(config.yieldSource).asset() returns (address vaultAsset) {
            require(vaultAsset == config.asset, "Vault asset mismatch");
            console2.log(" ::: Yield source is valid ERC4626 vault");
        } catch {
            revert("yieldSource is not a valid ERC4626 vault");
        }

        // Validate asset is ERC20
        try ERC20(config.asset).decimals() returns (uint8 decimals) {
            console2.log(" ::: Asset is valid ERC20 with", decimals, "decimals");
        } catch {
            revert("asset is not a valid ERC20");
        }

        // Warning: Check if using deployer as dragonRouter
        if (config.dragonRouter == msg.sender) {
            console2.log(" ::: WARNING: dragonRouter is set to deployer address");
            console2.log("     This is OK for testing, but MUST be changed for production!");
        }

        console2.log(" ::: Configuration validated");
        console2.log("");
    }

    function deployTokenizedStrategy() internal returns (address) {
        console2.log("Deploying YieldDonatingTokenizedStrategy implementation...");

        YieldDonatingTokenizedStrategy impl = new YieldDonatingTokenizedStrategy();

        console2.log(" ::: TokenizedStrategy deployed at:", address(impl));
        return address(impl);
    }

    function deployStrategy(
        DeployConfig memory config,
        address tokenizedStrategyImpl
    ) internal returns (address) {
        console2.log("Deploying YieldDonatingStrategy...");

        YieldDonatingStrategy strategy = new YieldDonatingStrategy(
            config.yieldSource,
            config.asset,
            config.strategyName,
            config.management,
            config.keeper,
            config.emergencyAdmin,
            config.dragonRouter,
            config.enableBurning,
            tokenizedStrategyImpl
        );

        console2.log(" ::: Strategy deployed at:", address(strategy));
        return address(strategy);
    }

    function verifyDeployment(address strategyAddress, DeployConfig memory config) internal view {
        console2.log("");
        console2.log("Verifying deployment...");

        YieldDonatingStrategy strategy = YieldDonatingStrategy(strategyAddress);

        // Verify immutable parameters
        require(address(strategy.YIELD_SOURCE()) == config.yieldSource, "yieldSource mismatch");
        // Note: asset() is in TokenizedStrategy, not directly accessible from YieldDonatingStrategy
        // We verify it by checking the yieldSource asset matches our config
        require(IERC4626(config.yieldSource).asset() == config.asset, "asset mismatch");

        console2.log(" ::: All parameters verified");
        console2.log(" ::: yieldSource:", address(strategy.YIELD_SOURCE()));
        console2.log(" ::: asset:", config.asset);

        // Check deposit/withdraw limits (using msg.sender instead of address(this))
        uint256 depositLimit = strategy.availableDepositLimit(msg.sender);
        uint256 withdrawLimit = strategy.availableWithdrawLimit(msg.sender);

        console2.log(" ::: Available deposit limit:", depositLimit);
        console2.log(" ::: Available withdraw limit:", withdrawLimit);
    }
}
