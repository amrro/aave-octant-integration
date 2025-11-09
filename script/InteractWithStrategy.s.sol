// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {YieldDonatingStrategy} from "../src/strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title Interact with YieldDonating Strategy
 * @notice Demonstrates complete user journey: deposit → yield accrual → report → withdrawal
 * 
 * SCENARIO:
 * 1. Alice deposits 1,000 USDC
 * 2. Bob deposits 500 USDC
 * 3. Time passes (30 days), Aave yields accrue
 * 4. Keeper calls report() to harvest yield
 * 5. Yield goes to dragonRouter (NOT back to users)
 * 6. Alice withdraws her principal (~1,000 USDC)
 * 7. Bob withdraws his principal (~500 USDC)
 */
contract InteractWithStrategy is Script {
    YieldDonatingStrategy public strategy;
    IERC20 public usdc;
    IERC4626 public aaveVault;
    
    // Addresses (strategy will be passed via env var or deployed)
    address public strategyAddress;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AAVE_VAULT_ADDRESS = 0x73edDFa87C71ADdC275c2b9890f5c3a8480bC9E6;
    
    // USDC whale for getting tokens (Binance hot wallet)
    address constant USDC_WHALE = 0x28C6c06298d514Db089934071355E5743bf21d60;
    
    // Actors
    address public alice;
    address public bob;
    address public keeper;
    address public dragonRouter;
    
    function setUp() public {
        // Try to get strategy address from env var, otherwise use the one from deployment
        strategyAddress = vm.envOr("STRATEGY_ADDRESS", address(0));
        
        if (strategyAddress == address(0)) {
            console.log("No STRATEGY_ADDRESS provided, deploying new strategy...");
            deployStrategy();
        }
        
        strategy = YieldDonatingStrategy(strategyAddress);
        usdc = IERC20(USDC_ADDRESS);
        aaveVault = IERC4626(AAVE_VAULT_ADDRESS);
        
        // Get role addresses from deployed strategy (cast to ITokenizedStrategy)
        ITokenizedStrategy tokenizedStrategy = ITokenizedStrategy(strategyAddress);
        keeper = tokenizedStrategy.keeper();
        dragonRouter = tokenizedStrategy.dragonRouter();
        
        // Create test users
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        console.log("=== Setup Complete ===");
        console.log("Strategy:", address(strategy));
        console.log("Alice:", alice);
        console.log("Bob:", bob);
        console.log("Keeper:", keeper);
        console.log("Dragon Router:", dragonRouter);
        console.log("");
    }
    
    function deployStrategy() internal {
        address deployer = msg.sender;
        
        // Deploy TokenizedStrategy implementation
        YieldDonatingTokenizedStrategy tokenizedStrategyImpl = new YieldDonatingTokenizedStrategy();
        
        // Deploy YieldDonatingStrategy
        YieldDonatingStrategy newStrategy = new YieldDonatingStrategy(
            AAVE_VAULT_ADDRESS,     // _yieldSource
            USDC_ADDRESS,           // _asset
            "Aave USDC YieldDonating Strategy", // _name
            deployer,               // _management
            deployer,               // _keeper
            deployer,               // _emergencyAdmin
            deployer,               // _donationAddress (dragonRouter)
            true,                   // _enableBurning
            address(tokenizedStrategyImpl) // _tokenizedStrategyAddress
        );
        
        strategyAddress = address(newStrategy);
        console.log("Strategy deployed at:", strategyAddress);
    }
    
    function run() public {
        setUp();
        
        console.log("=== SCENARIO: Full YieldDonating Flow ===\n");
        
        // Step 1: Fund users with USDC
        fundUsers();
        
        // Step 2: Users deposit
        aliceDeposits();
        bobDeposits();
        
        // Step 3: Check initial state
        checkState("After Deposits (Day 0)");
        
        // Step 4: Simulate time passing (30 days)
        simulateTimePassage();
        
        // Step 5: Check state before report
        checkState("Before Report (Day 30)");
        
        // Step 6: Keeper reports (harvests yield)
        keeperReports();
        
        // Step 7: Check state after report
        checkState("After Report (Day 30)");
        
        // Step 8: Users withdraw
        aliceWithdraws();
        bobWithdraws();
        
        // Step 9: Final state
        checkFinalState();
    }
    
    function fundUsers() internal {
        console.log("--- Step 1: Funding Users ---");
        
        // Impersonate USDC whale
        vm.startPrank(USDC_WHALE);
        
        // Transfer USDC to Alice and Bob
        usdc.transfer(alice, 10_000e6);  // 10k USDC
        usdc.transfer(bob, 10_000e6);    // 10k USDC
        
        vm.stopPrank();
        
        // Give them ETH for gas
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        
        console.log("Alice USDC balance:", usdc.balanceOf(alice) / 1e6, "USDC");
        console.log("Bob USDC balance:", usdc.balanceOf(bob) / 1e6, "USDC");
        console.log("");
    }
    
    function aliceDeposits() internal {
        console.log("--- Step 2a: Alice Deposits ---");
        
        uint256 depositAmount = 1_000e6; // 1,000 USDC
        
        vm.startPrank(alice);
        
        // Approve strategy
        usdc.approve(address(strategy), depositAmount);
        
        // Deposit and receive shares
        uint256 shares = IERC4626(address(strategy)).deposit(depositAmount, alice);
        
        console.log("Alice deposited:", depositAmount / 1e6, "USDC");
        console.log("Alice received:", shares / 1e6, "shares");
        console.log("Alice share balance:", IERC20(address(strategy)).balanceOf(alice) / 1e6);
        
        vm.stopPrank();
        console.log("");
    }
    
    function bobDeposits() internal {
        console.log("--- Step 2b: Bob Deposits ---");
        
        uint256 depositAmount = 500e6; // 500 USDC
        
        vm.startPrank(bob);
        
        // Approve strategy
        usdc.approve(address(strategy), depositAmount);
        
        // Deposit and receive shares
        uint256 shares = IERC4626(address(strategy)).deposit(depositAmount, bob);
        
        console.log("Bob deposited:", depositAmount / 1e6, "USDC");
        console.log("Bob received:", shares / 1e6, "shares");
        console.log("Bob share balance:", IERC20(address(strategy)).balanceOf(bob) / 1e6);
        
        vm.stopPrank();
        console.log("");
    }
    
    function simulateTimePassage() internal {
        console.log("--- Step 3: Time Passes (30 days) ---");
        console.log("Simulating 30 days of Aave yield accrual...");
        
        // Warp time forward 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Advance blocks (assuming ~12s per block)
        vm.roll(block.number + (30 days / 12));
        
        console.log("New block number:", block.number);
        console.log("New timestamp:", block.timestamp);
        console.log("");
    }
    
    function keeperReports() internal {
        console.log("--- Step 4: Keeper Reports (Harvests Yield) ---");
        
        uint256 dragonBalanceBefore = usdc.balanceOf(dragonRouter);
        
        vm.startPrank(keeper);
        
        // Call report to harvest yield (cast to ITokenizedStrategy)
        ITokenizedStrategy tokenizedStrategy = ITokenizedStrategy(address(strategy));
        (uint256 profit, uint256 loss) = tokenizedStrategy.report();
        
        vm.stopPrank();
        
        uint256 dragonBalanceAfter = usdc.balanceOf(dragonRouter);
        uint256 yieldHarvested = dragonBalanceAfter - dragonBalanceBefore;
        
        console.log("Profit reported:", profit / 1e6, "USDC");
        console.log("Loss reported:", loss / 1e6, "USDC");
        console.log("Yield sent to dragonRouter:", yieldHarvested / 1e6, "USDC");
        console.log("DragonRouter balance:", dragonBalanceAfter / 1e6, "USDC");
        console.log("");
    }
    
    function aliceWithdraws() internal {
        console.log("--- Step 5a: Alice Withdraws ---");
        
        uint256 aliceShares = IERC20(address(strategy)).balanceOf(alice);
        uint256 usdcBefore = usdc.balanceOf(alice);
        
        vm.startPrank(alice);
        
        // Redeem all shares
        uint256 assetsReceived = IERC4626(address(strategy)).redeem(aliceShares, alice, alice);
        
        vm.stopPrank();
        
        uint256 usdcAfter = usdc.balanceOf(alice);
        
        console.log("Alice redeemed:", aliceShares / 1e6, "shares");
        console.log("Alice received:", assetsReceived / 1e6, "USDC");
        console.log("Alice final USDC balance:", usdcAfter / 1e6, "USDC");
        console.log("");
    }
    
    function bobWithdraws() internal {
        console.log("--- Step 5b: Bob Withdraws ---");
        
        uint256 bobShares = IERC20(address(strategy)).balanceOf(bob);
        uint256 usdcBefore = usdc.balanceOf(bob);
        
        vm.startPrank(bob);
        
        // Redeem all shares
        uint256 assetsReceived = IERC4626(address(strategy)).redeem(bobShares, bob, bob);
        
        vm.stopPrank();
        
        uint256 usdcAfter = usdc.balanceOf(bob);
        
        console.log("Bob redeemed:", bobShares / 1e6, "shares");
        console.log("Bob received:", assetsReceived / 1e6, "USDC");
        console.log("Bob final USDC balance:", usdcAfter / 1e6, "USDC");
        console.log("");
    }
    
    function checkState(string memory label) internal view {
        console.log("--- State Check:", label, "---");
        
        IERC4626 vault = IERC4626(address(strategy));
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = IERC20(address(strategy)).totalSupply();
        uint256 aliceShares = IERC20(address(strategy)).balanceOf(alice);
        uint256 bobShares = IERC20(address(strategy)).balanceOf(bob);
        
        console.log("Total Assets (in strategy):", totalAssets / 1e6, "USDC");
        console.log("Total Supply (shares):", totalSupply / 1e6);
        console.log("Alice shares:", aliceShares / 1e6);
        console.log("Bob shares:", bobShares / 1e6);
        
        // Check conversion rates
        if (aliceShares > 0) {
            uint256 aliceAssets = vault.convertToAssets(aliceShares);
            console.log("Alice can withdraw:", aliceAssets / 1e6, "USDC");
        }
        
        if (bobShares > 0) {
            uint256 bobAssets = vault.convertToAssets(bobShares);
            console.log("Bob can withdraw:", bobAssets / 1e6, "USDC");
        }
        
        console.log("");
    }
    
    function checkFinalState() internal view {
        console.log("=== FINAL STATE ===");
        
        IERC4626 vault = IERC4626(address(strategy));
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = IERC20(address(strategy)).totalSupply();
        uint256 dragonBalance = usdc.balanceOf(dragonRouter);
        
        console.log("Strategy total assets:", totalAssets / 1e6, "USDC (should be ~0)");
        console.log("Strategy total supply:", totalSupply / 1e6, "shares (should be ~0)");
        console.log("DragonRouter balance:", dragonBalance / 1e6, "USDC (yield donated here)");
        console.log("");
        console.log("=== KEY INSIGHT ===");
        console.log("- Users deposited 1,500 USDC total");
        console.log("- Users withdrew ~1,500 USDC (principal)");
        console.log("- Yield went to dragonRouter (NOT users)");
        console.log("- This is YIELD DONATING in action!");
    }
}
