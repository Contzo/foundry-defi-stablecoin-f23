# 🪙 Foundry DSC Stablecoin — Enhanced Version

This project extends the [Cyfrin DeFi Stablecoin](https://github.com/Cyfrin/foundry-defi-stablecoin-cu) by introducing protocol-level safety mechanisms and yield incentives. It maintains the core principles of a decentralized, overcollateralized stablecoin while improving system robustness and user engagement.

> ✅ Built with [Foundry](https://book.getfoundry.sh/), for high-performance smart contract development and testing.

---

## ⚙️ Key Features

### 💵 Dollar-Pegged Stablecoin (DSC)
- Backed by WETH and WBTC collateral.
- Overcollateralization required for minting.
- Supports minting, redemption, and liquidation workflows.

### 🛑 Time-Based Circuit Breaker (New!)
- Activated manually or during abnormal conditions.
- **Temporarily halts sensitive actions** like minting or withdrawals.
- Automatically resets after a configurable cooldown period.
- Helps the system recover during oracle disruptions or volatility.

### 📈 Staking Pool with Yield Emission (New!)
- Users can stake DSC to mint SDSC (Staked DSC).
- Yield is distributed proportionally based on:
  - Stake share
  - Emission rate
  - Time elapsed since last claim
- **Protocol fees fund the yield pool**:
  - A small portion of deposited collateral is taxed.
  - That tax is burned.
  - An equivalent amount of DSC (pegged to USD) is minted and sent to the pool.

---

## 📂 Environment Setup

Before running or testing the contracts, you'll need a `.env` file at the root of the repo. I used the default Anvil private key account. 

### 🔐 `.env` Example

```ini
# Default private key from Anvil (DO NOT use in production!)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
