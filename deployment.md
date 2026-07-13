# TrustFundX – Deployment Guide

> Complete step-by-step instructions to deploy TrustFundX on Aptos Devnet, Testnet, and via Remix IDE with Welldone Wallet.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install Aptos CLI](#2-install-aptos-cli)
3. [Configure Your Wallet](#3-configure-your-wallet)
4. [Fund Your Devnet Account](#4-fund-your-devnet-account)
5. [Configure Move.toml](#5-configure-movetoml)
6. [Compile the Contract](#6-compile-the-contract)
7. [Run Tests](#7-run-tests)
8. [Publish to Devnet](#8-publish-to-devnet)
9. [Publish to Testnet](#9-publish-to-testnet)
10. [Execute Every Entry Function](#10-execute-every-entry-function)
11. [Verify Events on Explorer](#11-verify-events-on-explorer)
12. [Remix IDE + Welldone Wallet](#12-remix-ide--welldone-wallet)
13. [Save Contract Address](#13-save-contract-address)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

Ensure you have the following installed:

| Tool | Minimum Version | Check Command |
|---|---|---|
| Aptos CLI | 3.0.0+ | `aptos --version` |
| Git | Any | `git --version` |
| Node.js (optional, for scripts) | 18+ | `node --version` |

---

## 2. Install Aptos CLI

### Option A – Official Installer (Recommended)

**macOS / Linux:**
```bash
curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3
```

**Windows (PowerShell):**
```powershell
iwr "https://aptos.dev/scripts/install_cli.py" -useb | python
```

### Option B – Homebrew (macOS)
```bash
brew install aptos
```

### Option C – Cargo (Rust)
```bash
cargo install aptos
```

### Verify Installation
```bash
aptos --version
# Output: aptos 3.x.x
```

---

## 3. Configure Your Wallet

### Initialize a New Profile (Devnet)

```bash
# Navigate to your project directory
cd "path/to/TrustFundX"

# Initialize for devnet (creates ~/.aptos/config.yaml)
aptos init --network devnet

# When prompted:
# > Choose network: devnet
# > Enter private key: [press Enter to generate new key]
# > Output: Account address: 0xYOUR_ACCOUNT_ADDRESS
```

### View Your Configuration
```bash
aptos config show-global-config
```

### List All Profiles
```bash
aptos config show-profiles
```

### Your Account Address
```bash
aptos account list
# Note the address shown — this will be your vault_address
```

---

## 4. Fund Your Devnet Account

Devnet accounts need test APT to pay for transactions.

```bash
# Method 1: Aptos CLI faucet
aptos account fund-with-faucet \
  --account default \
  --amount 100000000

# Method 2: Aptos Devnet Faucet UI
# Visit: https://aptos.dev/network/faucet
# Enter your address and request tokens

# Verify balance
aptos account balance --account default
```

> ⚠️ **Note**: Devnet is reset periodically. Re-fund when needed.

---

## 5. Configure Move.toml

Open `Move.toml` and update the address placeholder:

```toml
[addresses]
# Replace with YOUR actual Aptos account address
trustfundx = "0xYOUR_ACCOUNT_ADDRESS"
```

Example:
```toml
[addresses]
trustfundx = "0x1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890"
```

> **Note**: For `aptos move test`, `Move.toml` uses `dev-addresses`:
> ```toml
> [dev-addresses]
> trustfundx = "0xCAFE"
> ```
> This is already configured — tests run without changing anything.

---

## 6. Compile the Contract

```bash
# Compile with your address
aptos move compile \
  --named-addresses trustfundx=<YOUR_ADDRESS>

# Example:
aptos move compile \
  --named-addresses trustfundx=0x1a2b3c4d5e6f...

# Expected output:
# Compiling, may take a little while to download git dependencies...
# INCLUDING DEPENDENCY MoveStdlib
# INCLUDING DEPENDENCY AptosStdlib
# INCLUDING DEPENDENCY AptosFramework
# BUILDING TrustFundX
# {
#   "Result": [
#     "0x<YOUR_ADDRESS>::vault"
#   ]
# }
```

If compilation fails, check:
- The `Move.toml` address is correct
- Your Aptos CLI version is up to date
- Network connectivity (downloads dependencies from GitHub)

---

## 7. Run Tests

```bash
# Run all 25 unit tests (uses 0xCAFE from dev-addresses)
aptos move test

# Run with verbose mode to see each test name
aptos move test --verbose

# Run a specific test by name
aptos move test --filter test_deposit

# Run with coverage report
aptos move test --compute-coverage

# Expected final output:
# Test result: OK. 25 passed; 0 failed; 0 skipped
# Total time: Xs
```

---

## 8. Publish to Devnet

```bash
# Step 1: Compile first (required before publish)
aptos move compile \
  --named-addresses trustfundx=<YOUR_ADDRESS>

# Step 2: Publish the module
aptos move publish \
  --named-addresses trustfundx=<YOUR_ADDRESS> \
  --assume-yes \
  --profile default

# Example output:
# Compiling, may take a little while to download git dependencies...
# BUILDING TrustFundX
# package size 8000 bytes
# Do you want to submit a transaction for a range of [X - Y] Octas at a gas unit price of Z Octas? [yes/no]
# yes
# {
#   "Result": {
#     "transaction_hash": "0xABC...",
#     "gas_used": 1234,
#     "gas_unit_price": 100,
#     "sender": "0x<YOUR_ADDRESS>",
#     "sequence_number": 0,
#     "success": true,
#     "version": 123456789,
#     "vm_status": "Executed successfully"
#   }
# }
```

> 💾 **Save the `transaction_hash`** — you can verify the deployment on Aptos Explorer.

---

## 9. Publish to Testnet

```bash
# Initialize a testnet profile
aptos init \
  --network testnet \
  --profile testnet

# Fund testnet account
aptos account fund-with-faucet \
  --account testnet \
  --amount 100000000 \
  --profile testnet

# Compile and publish on testnet
aptos move publish \
  --named-addresses trustfundx=<YOUR_TESTNET_ADDRESS> \
  --profile testnet \
  --assume-yes
```

---

## 10. Execute Every Entry Function

Replace `<ADDR>` with your deployed contract address throughout.

### 10.1 Initialize Vault

```bash
aptos move run \
  --function-id '<ADDR>::vault::init_vault' \
  --assume-yes

# Verify:
aptos move view \
  --function-id '<ADDR>::vault::vault_exists' \
  --args address:<ADDR>
# Expected: { "Result": [true] }
```

### 10.2 Deposit Tokens (10 APT = 1,000,000,000 Octas)

```bash
aptos move run \
  --function-id '<ADDR>::vault::deposit_tokens' \
  --args address:<ADDR> u64:1000000000 \
  --assume-yes

# Verify available balance:
aptos move view \
  --function-id '<ADDR>::vault::get_available_balance' \
  --args address:<ADDR>
# Expected: { "Result": [1000000000] }
```

### 10.3 Allocate Tokens (3 APT to a beneficiary)

```bash
aptos move run \
  --function-id '<ADDR>::vault::allocate_tokens' \
  --args \
    address:<ADDR> \
    address:<BENEFICIARY_ADDR> \
    u64:300000000 \
  --assume-yes

# Verify claimable:
aptos move view \
  --function-id '<ADDR>::vault::get_claimable_balance' \
  --args address:<ADDR> address:<BENEFICIARY_ADDR>
# Expected: { "Result": [300000000] }
```

### 10.4 Claim Tokens (as Beneficiary)

```bash
# Switch to beneficiary profile first
aptos init --profile beneficiary --network devnet

aptos move run \
  --function-id '<ADDR>::vault::claim_tokens' \
  --args address:<ADDR> \
  --profile beneficiary \
  --assume-yes

# Verify claimed:
aptos move view \
  --function-id '<ADDR>::vault::has_claimed' \
  --args address:<ADDR> address:<BENEFICIARY_ADDR>
# Expected: { "Result": [true] }
```

### 10.5 Withdraw Tokens (2 APT)

```bash
aptos move run \
  --function-id '<ADDR>::vault::withdraw_tokens' \
  --args address:<ADDR> u64:200000000 \
  --assume-yes

# Verify remaining balance:
aptos move view \
  --function-id '<ADDR>::vault::get_available_balance' \
  --args address:<ADDR>
```

### 10.6 Transfer Admin

```bash
aptos move run \
  --function-id '<ADDR>::vault::transfer_admin' \
  --args address:<ADDR> address:<NEW_ADMIN_ADDR> \
  --assume-yes

# Verify new admin:
aptos move view \
  --function-id '<ADDR>::vault::get_admin' \
  --args address:<ADDR>
# Expected: { "Result": ["<NEW_ADMIN_ADDR>"] }
```

---

## 11. Verify Events on Explorer

1. Visit **[Aptos Explorer](https://explorer.aptoslabs.com)** (select Devnet or Testnet)
2. Search for your account address: `0xYOUR_ADDRESS`
3. Click on **"Events"** tab
4. You should see:
   - `VaultCreatedEvent`
   - `DepositEvent`
   - `AllocateEvent`
   - `ClaimEvent`
   - `WithdrawEvent`
   - `AdminTransferredEvent`

Each event includes a timestamp, the relevant addresses, and the amounts transacted.

---

## 12. Remix IDE + Welldone Wallet

TrustFundX can also be deployed using the **Aptos Remix IDE plugin** with **Welldone Wallet**.

### Step 1: Open Remix IDE

Navigate to: **[https://remix.ethereum.org](https://remix.ethereum.org)**

### Step 2: Install the Aptos Plugin

1. Click **Plugin Manager** (plug icon in left sidebar)
2. Search for **"Aptos"**
3. Click **Activate** on the Aptos plugin
4. The Aptos tab will appear in the left sidebar

### Step 3: Install Welldone Wallet

1. Install the **[Welldone Wallet](https://welldonestudio.io/wallet)** browser extension
2. Create a new account or import your existing key
3. Switch network to **Devnet** or **Testnet**

### Step 4: Load Your Contract

1. In Remix, create the folder structure:
   ```
   contracts/trustfundx.move
   Move.toml
   ```
2. Copy-paste your `trustfundx.move` content
3. Update `Move.toml` with your Welldone Wallet address

### Step 5: Compile in Remix

1. Click the **Aptos** plugin tab
2. Click **Compile** (ensure `trustfundx.move` is selected)
3. Wait for "Compilation successful" message

### Step 6: Connect Welldone Wallet

1. In the Aptos plugin panel, click **Connect Wallet**
2. Select **Welldone Wallet**
3. Approve the connection in the browser extension

### Step 7: Deploy

1. In the Aptos plugin, click **Deploy**
2. Confirm the transaction in Welldone Wallet
3. Copy the deployed module address

### Step 8: Interact via Remix

After deployment, use the **function call interface** in the Remix Aptos plugin to:
- Call `init_vault`
- Call `deposit_tokens` with args
- Call `allocate_tokens`, `claim_tokens`, etc.
- Query view functions

---

## 13. Save Contract Address

After deployment, record these values in a safe location:

```
# TrustFundX Deployment Record
Date:             ____________________
Network:          Devnet / Testnet / Mainnet
Deployer Address: 0x____________________
Vault Address:    0x____________________  (= Deployer Address)
Tx Hash (deploy): 0x____________________
Aptos CLI version: ____________________
```

---

## 14. Troubleshooting

### "Module not found" error
```bash
# Ensure Move.toml address matches your account
aptos account list  # Check your address
# Update Move.toml: trustfundx = "0xYOUR_CORRECT_ADDRESS"
```

### "Insufficient balance" during publish
```bash
# Re-fund your account
aptos account fund-with-faucet --account default --amount 200000000
```

### "E_VAULT_NOT_FOUND" (error code 3)
- Ensure you ran `init_vault` before any other function
- Verify the vault_address matches the deployer's address

### Dependency download failures
```bash
# Clear cached dependencies
rm -rf ~/.move/
# Re-compile (will re-download)
aptos move compile --named-addresses trustfundx=<ADDR>
```

### Network connectivity issues
```bash
# Check Aptos node status
aptos node health-check --url https://fullnode.devnet.aptoslabs.com/v1
```

---

*For more help, visit the [Aptos Developer Docs](https://aptos.dev) or open an issue on the TrustFundX GitHub repository.*
