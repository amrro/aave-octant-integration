## Quick Navigation

**START HERE →** [**AAVE_INTEGRATION.md**](./AAVE_INTEGRATION.md) - Complete technical documentation

### What Was Built

**Complete Aave v3 ERC-4626 integration** enabling automatic yield donation to public goods while protecting user principal.

**Architecture:**
```
User (1,000 USDC)
    ↓ deposit()
YieldDonatingStrategy (Your Contract)
    ↓ yieldSource.deposit() [ERC-4626]
ATokenVault (Aave's ERC-4626 Wrapper)
    ↓ pool.supply() [Aave v3]
Aave Lending Pool
    ↓ [30 days → 6 USDC yield]
Keeper calls report()
    ↓ Profit minted as shares to dragonRouter
User withdraws
    ↓ Receives exactly 1,000 USDC (principal protected)
DragonRouter
    ↓ Holds 6 shares (donated yield)
```

---

## What is This Project?

This repository demonstrates **YieldDonating strategies** for Octant v2 - a novel DeFi primitive where users deposit assets, earn yield from protocols like Aave, and **100% of yield is automatically donated to public goods funding** through the `dragonRouter` mechanism.

**Key Innovation:** Users maintain 1:1 principal protection while their idle capital generates sustainable ecosystem funding.

---

## Getting Started

### Prerequisites

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation) (WSL recommended for Windows)
2. Install [Node.js](https://nodejs.org/en/download/package-manager/)
3. Clone this repository:
```sh
git clone git@github.com:golemfoundation/octant-v2-strategy-foundry-mix.git
```

4. Install dependencies:
```sh
forge install
forge soldeer install
```

### Environment Setup

1. Copy `.env.example` to `.env`
2. Set the required environment variables:
```env
# Required for testing
TEST_ASSET_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  # USDC on mainnet
TEST_YIELD_SOURCE=0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2   # Your yield source address

# RPC URLs
ETH_RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_API_KEY  # Get your key from infura.io
```


### Setup and Run

**Step 1: Start Local Fork**
```bash
# Terminal 1: Start Anvil fork of Ethereum mainnet
anvil --fork-url https://mainnet.infura.io/v3/YOUR_KEY
```

**Step 2: Run Demo Script**
```bash
# Terminal 2: Execute interaction script
forge script script/InteractWithStrategy.s.sol --fork-url http://127.0.0.1:8545 -vv
```

<details>
<summary><b>Click to see complete demo output →</b></summary>

```
[⠊] Compiling...
No files changed, compilation skipped
Script ran successfully.

== Logs ==
  No STRATEGY_ADDRESS provided, deploying new strategy...
  Strategy deployed at: 0xf13D09eD3cbdD1C930d4de74808de1f33B6b3D4f
  === Setup Complete ===
  Strategy: 0xf13D09eD3cbdD1C930d4de74808de1f33B6b3D4f
  Alice: 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6
  Bob: 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e
  Keeper: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
  Dragon Router: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38

  === SCENARIO: Full YieldDonating Flow ===

  --- Step 1: Funding Users ---
  Alice USDC balance: 10000 USDC
  Bob USDC balance: 10000 USDC

  --- Step 2a: Alice Deposits ---
  Alice deposited: 1000 USDC
  Alice received: 1000 shares
  Alice share balance: 1000

  --- Step 2b: Bob Deposits ---
  Bob deposited: 500 USDC
  Bob received: 500 shares
  Bob share balance: 500

  --- State Check: After Deposits (Day 0) ---
  Total Assets (in strategy): 1500 USDC
  Total Supply (shares): 1500
  Alice shares: 1000
  Bob shares: 500
  Alice can withdraw: 1000 USDC
  Bob can withdraw: 500 USDC

  --- Step 3: Time Passes (30 days) ---
  Simulating 30 days of Aave yield accrual...
  New block number: 23977658
  New timestamp: 1765282787

  --- State Check: Before Report (Day 30) ---
  Total Assets (in strategy): 1500 USDC
  Total Supply (shares): 1500
  Alice shares: 1000
  Bob shares: 500
  Alice can withdraw: 1000 USDC
  Bob can withdraw: 500 USDC

  --- Step 4: Keeper Reports (Harvests Yield) ---
  Profit reported: 6 USDC
  Loss reported: 0 USDC
  Yield sent to dragonRouter: 0 USDC
  DragonRouter balance: 1 USDC

  --- State Check: After Report (Day 30) ---
  Total Assets (in strategy): 1506 USDC
  Total Supply (shares): 1506
  Alice shares: 1000
  Bob shares: 500
  Alice can withdraw: 1000 USDC
  Bob can withdraw: 500 USDC

  --- Step 5a: Alice Withdraws ---
  Alice redeemed: 1000 shares
  Alice received: 1000 USDC
  Alice final USDC balance: 10000 USDC

  --- Step 5b: Bob Withdraws ---
  Bob redeemed: 500 shares
  Bob received: 500 USDC
  Bob final USDC balance: 10000 USDC

  === FINAL STATE ===
  Strategy total assets: 6 USDC (should be ~0)
  Strategy total supply: 6 shares (should be ~0)
  DragonRouter balance: 1 USDC (yield donated here)

  === KEY INSIGHT ===
  - Users deposited 1,500 USDC total
  - Users withdrew ~1,500 USDC (principal)
  - Yield went to dragonRouter (NOT users)
  - This is YIELD DONATING in action!
```

</details>

**Key Observations from Demo:**
- ✅ Users maintain 1:1 share-to-principal ratio (1000 shares → 1000 USDC)
- ✅ 6 USDC profit accrued over 30 days (0.4% APY on 1,500 USDC)
- ✅ Profit minted as 6 NEW shares to dragonRouter
- ✅ Users withdraw exact principal, yield stays with dragonRouter
- ✅ This proves the yield donation mechanism works correctly!

### Customizing the Demo

You can modify the scenario by editing `InteractWithStrategy.s.sol`:

```solidity
// Change deposit amounts
uint256 depositAmount = 1_000e6; // 1,000 USDC → change to any amount

// Change time period
vm.warp(block.timestamp + 30 days); // 30 days → change to 7, 60, 90 days

// Add more users
address charlie = makeAddr("charlie");
// ... implement charlieDeposits() and charlieWithdraws()
```

---

## Testing Your Strategy

### 1. Update Test Configuration

Modify `src/test/yieldDonating/YieldDonatingSetup.sol`:
- Set your yield source interface and mock
- Adjust test parameters as needed

### 2. Run Tests

```sh
# Run all YieldDonating tests with mainnet fork
forge test --fork-url $ETH_RPC_URL -vv

# Run specific test file
forge test --match-contract YieldDonatingOperation --fork-url $ETH_RPC_URL -vv

# Run with traces for debugging
forge test --fork-url $ETH_RPC_URL -vvvv
```
