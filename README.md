<div align="center">

# 🏦 TrustFundX

### Decentralized AI-Powered Token Vault & Fund Management Platform

[![Aptos](https://img.shields.io/badge/Aptos-Move-00C2FF?style=for-the-badge&logo=aptos)](https://aptos.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/badge/Tests-25%20Passing-brightgreen?style=for-the-badge)](./tests/)
[![Coverage](https://img.shields.io/badge/Coverage-95%25+-success?style=for-the-badge)](./tests/)
[![Network](https://img.shields.io/badge/Network-Devnet%20%7C%20Testnet-blue?style=for-the-badge)](https://aptos.dev)

> A production-ready, secure Aptos Move smart contract for decentralized token vault management — featuring deposits, allocations, claims, withdrawals, and admin ownership transfer.

</div>

---

## 📖 Table of Contents

- [Project Overview](#-project-overview)
- [Features](#-features)
- [Architecture](#-architecture)
- [Smart Contract Design](#-smart-contract-design)
- [Vault Workflow](#-vault-workflow)
- [Project Structure](#-project-structure)
- [Installation](#-installation)
- [Compilation](#-compilation)
- [Testing](#-testing)
- [Deployment](#-deployment)
- [Function Documentation](#-function-documentation)
- [Example Transactions](#-example-transactions)
- [Event System](#-event-system)
- [Error Codes](#-error-codes)
- [Gas Estimation](#-gas-estimation)
- [Future Improvements](#-future-improvements)
- [License](#-license)

---

## 🌟 Project Overview

**TrustFundX** is a secure, fully on-chain token vault built on the **Aptos blockchain** using the **Move programming language**. It enables:

- **Admins** to create vaults, deposit APT, allocate funds to beneficiaries, withdraw unused funds, and transfer vault ownership.
- **Beneficiaries** to claim their allocated APT directly to their wallets.
- **Full auditability** via on-chain events for every state transition.

The contract is designed with a **zero-trust security model** — every function directly accesses the vault via its address, with no address derivation from admin keys.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🏗️ **Vault Creation** | Initialize a secure vault at your Aptos account address |
| 💰 **Token Deposit** | Deposit APT into the vault (admin only) |
| 📤 **Token Allocation** | Allocate specific amounts to beneficiary addresses |
| 🎁 **Beneficiary Claiming** | Beneficiaries can pull their allocated APT |
| 💸 **Admin Withdrawal** | Withdraw unallocated funds back to admin wallet |
| 👑 **Admin Transfer** | Transfer vault ownership to a new admin |
| 📊 **Balance Tracking** | Real-time tracking of total, available, and allocated balances |
| 📜 **Full Event Logging** | Every action emits an on-chain event |
| 🔐 **Security Hardened** | 10 error codes covering all attack vectors |
| 🧪 **95%+ Test Coverage** | 25 comprehensive unit tests |

---

## 🏛️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      TrustFundX                         │
│                  trustfundx::vault                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────┐    ┌──────────────────────────────────┐   │
│  │  Admin  │───▶│           Vault Resource          │   │
│  └─────────┘    │  stored at vault_address          │   │
│                 │                                   │   │
│                 │  admin: address                   │   │
│                 │  total_deposited: u64             │   │
│                 │  available_balance: u64           │   │
│                 │  allocated_balance: u64           │   │
│                 │  coin_store: Coin<AptosCoin>      │   │
│                 │  allocations: Table<addr, u64>    │   │
│                 │  claimed: Table<addr, bool>       │   │
│                 │  claim_amounts: Table<addr, u64>  │   │
│                 │  [6 EventHandle fields]           │   │
│                 └──────────────────────────────────┘   │
│                          │                              │
│               ┌──────────┴──────────┐                   │
│               │                     │                   │
│         ┌─────▼──────┐      ┌───────▼────┐             │
│         │Beneficiary │      │ Blockchain  │             │
│         │  Claims    │      │   Events    │             │
│         └────────────┘      └────────────┘             │
└─────────────────────────────────────────────────────────┘
```

---

## 📐 Smart Contract Design

### Module

```
Module: trustfundx::vault
File:   contracts/trustfundx.move
```

### Core Resource

The `Vault` struct is stored as a **Move resource** at the admin's account address. It uses:

- **`Table<address, u64>`** for O(1) allocation lookups
- **`Coin<AptosCoin>`** as the actual on-chain coin store (no off-chain escrow)
- **`EventHandle`** for each event category

### Security Invariants

| Invariant | Enforcement |
|---|---|
| `available_balance + allocated_balance == coin::value(coin_store)` | Maintained after every mutation |
| `claimed[b] == true → allocation[b] exists` | Table access guards |
| `total_deposited >= available_balance + allocated_balance` | Withdraw only reduces available |
| `vault.admin == caller` | All admin functions |

---

## 🔄 Vault Workflow

```
Admin                    Vault                  Beneficiary
  │                        │                        │
  │──── init_vault() ─────▶│                        │
  │                        │ [VaultCreatedEvent]    │
  │                        │                        │
  │──── deposit_tokens() ──▶│                        │
  │                        │ [DepositEvent]         │
  │                        │                        │
  │──── allocate_tokens() ─▶│                        │
  │                        │ [AllocateEvent]        │
  │                        │                        │
  │                        │◀──── claim_tokens() ───│
  │                        │ [ClaimEvent]           │
  │                        │─── APT Transfer ──────▶│
  │                        │                        │
  │──── withdraw_tokens() ─▶│                        │
  │                        │ [WithdrawEvent]        │
  │◀─── APT Transfer ───────│                        │
  │                        │                        │
  │──── transfer_admin() ──▶│                        │
  │                        │ [AdminTransferredEvent]│
```

---

## 📁 Project Structure

```
TrustFundX/
├── contracts/
│   └── trustfundx.move         # Core smart contract
├── tests/
│   └── trustfundx_tests.move   # 25 unit tests
├── Move.toml                   # Aptos project manifest
├── README.md                   # This file
├── deployment.md               # Deployment guide
└── security.md                 # Security documentation
```

---

## ⚙️ Installation

### Prerequisites

| Tool | Version | Link |
|---|---|---|
| Aptos CLI | ≥ 3.0.0 | [Install Guide](https://aptos.dev/tools/aptos-cli/install-aptos-cli) |
| Move Compiler | Bundled with Aptos CLI | — |
| Git | Any | [git-scm.com](https://git-scm.com) |

### Clone the Repository

```bash
git clone https://github.com/yourusername/TrustFundX.git
cd TrustFundX
```

### Initialize Aptos Account (First Time)

```bash
# Initialize for devnet
aptos init --network devnet

# Fund your account with faucet
aptos account fund-with-faucet --account default
```

---

## 🔨 Compilation

```bash
# Get your account address first
aptos account list

# Compile (replace <YOUR_ADDRESS> with your Aptos account address)
aptos move compile \
  --named-addresses trustfundx=<YOUR_ADDRESS>

# Expected output:
# Compiling, may take a little while to download git dependencies...
# INCLUDING DEPENDENCY AptosFramework
# INCLUDING DEPENDENCY AptosStdlib
# INCLUDING DEPENDENCY MoveStdlib
# BUILDING TrustFundX
# {
#   "Result": ["<YOUR_ADDRESS>::vault"]
# }
```

---

## 🧪 Testing

```bash
# Run all tests (uses dev-addresses from Move.toml: trustfundx = "0xCAFE")
aptos move test

# Run tests with verbose output
aptos move test --verbose

# Run a specific test
aptos move test --filter test_deposit

# Run with gas profiling
aptos move test --compute-coverage

# Expected output:
# Running Move unit tests
# [ PASS ] trustfundx::vault_tests::test_init_vault
# [ PASS ] trustfundx::vault_tests::test_double_init_vault
# [ PASS ] trustfundx::vault_tests::test_deposit
# [ PASS ] trustfundx::vault_tests::test_zero_deposit
# ... (25 tests total)
# Test result: OK. 25 passed; 0 failed; 0 skipped
```

### Test Coverage Summary

| Category | Tests | Status |
|---|---|---|
| Vault Initialization | 2 | ✅ |
| Deposits | 3 | ✅ |
| Allocations | 4 | ✅ |
| Claims | 3 | ✅ |
| Withdrawals | 3 | ✅ |
| Admin Transfer | 5 | ✅ |
| Edge Cases | 5 | ✅ |
| **Total** | **25** | **✅ All Pass** |

---

## 🚀 Deployment

See(https://aptos-trustfundx-project.vercel.app/) for the full step-by-step guide.

**Quick Deploy to Devnet:**

```bash
# 1. Compile
aptos move compile --named-addresses trustfundx=<YOUR_ADDRESS>

# 2. Publish
aptos move publish \
  --named-addresses trustfundx=<YOUR_ADDRESS> \
  --assume-yes

# 3. Initialize your vault
aptos move run \
  --function-id '<YOUR_ADDRESS>::vault::init_vault' \
  --assume-yes
```

---

## 📚 Function Documentation

### Entry Functions

#### `init_vault(admin: &signer)`
Creates a new vault at the admin's Aptos account address.
- **Signer**: Admin account
- **Effect**: Vault resource created at `signer::address_of(admin)`
- **Events**: `VaultCreatedEvent`
- **Aborts**: `E_VAULT_EXISTS` if vault already exists

---

#### `deposit_tokens(admin, vault_address, amount)`
Deposits `amount` Octas of APT into the vault.
- **Signer**: Admin
- **Params**: `vault_address: address`, `amount: u64` (Octas)
- **Effect**: Increases `available_balance` and `total_deposited`
- **Events**: `DepositEvent`
- **Aborts**: `E_NOT_ADMIN`, `E_INVALID_AMOUNT`, `E_OVERFLOW`

---

#### `allocate_tokens(admin, vault_address, beneficiary, amount)`
Allocates `amount` Octas to a beneficiary address.
- **Signer**: Admin
- **Params**: `vault_address: address`, `beneficiary: address`, `amount: u64`
- **Effect**: Moves funds from `available_balance` → `allocated_balance`
- **Events**: `AllocateEvent`
- **Aborts**: `E_NOT_ADMIN`, `E_INVALID_AMOUNT`, `E_INVALID_RECIPIENT`, `E_INSUFFICIENT_BALANCE`, `E_ALREADY_CLAIMED`

---

#### `claim_tokens(beneficiary, vault_address)`
Claims the caller's full allocation from the vault.
- **Signer**: Beneficiary (any address with an allocation)
- **Params**: `vault_address: address`
- **Effect**: Transfers allocated APT to beneficiary; marks as claimed
- **Events**: `ClaimEvent`
- **Aborts**: `E_NOT_ALLOCATED`, `E_ALREADY_CLAIMED`, `E_INVALID_AMOUNT`

---

#### `withdraw_tokens(admin, vault_address, amount)`
Withdraws unallocated APT from the vault to the admin wallet.
- **Signer**: Admin
- **Params**: `vault_address: address`, `amount: u64`
- **Effect**: Reduces `available_balance`; returns APT to admin
- **Events**: `WithdrawEvent`
- **Aborts**: `E_NOT_ADMIN`, `E_INVALID_AMOUNT`, `E_INSUFFICIENT_BALANCE`

---

#### `transfer_admin(admin, vault_address, new_admin)`
Transfers vault ownership to a new admin.
- **Signer**: Current admin
- **Params**: `vault_address: address`, `new_admin: address`
- **Effect**: Updates `vault.admin`; full vault state preserved
- **Events**: `AdminTransferredEvent`
- **Aborts**: `E_NOT_ADMIN`, `E_INVALID_ADMIN` (zero address or self)

---

### View Functions

| Function | Params | Returns | Description |
|---|---|---|---|
| `get_admin` | `vault_address` | `address` | Current vault admin |
| `get_total_balance` | `vault_address` | `u64` | Cumulative deposits |
| `get_available_balance` | `vault_address` | `u64` | Unallocated balance |
| `get_allocated_balance` | `vault_address` | `u64` | Locked allocations |
| `get_claimable_balance` | `vault_address, beneficiary` | `u64` | Pending claim amount |
| `has_claimed` | `vault_address, beneficiary` | `bool` | Whether claimed |
| `vault_exists` | `vault_address` | `bool` | Vault exists check |

---

## 💡 Example Transactions

### 1. Create Vault
```bash
aptos move run \
  --function-id '<ADDR>::vault::init_vault' \
  --assume-yes
```

### 2. Deposit 10 APT
```bash
aptos move run \
  --function-id '<ADDR>::vault::deposit_tokens' \
  --args address:<VAULT_ADDR> u64:1000000000 \
  --assume-yes
```

### 3. Allocate 3 APT to Beneficiary
```bash
aptos move run \
  --function-id '<ADDR>::vault::allocate_tokens' \
  --args address:<VAULT_ADDR> address:<BENEFICIARY_ADDR> u64:300000000 \
  --assume-yes
```

### 4. Claim Tokens (Beneficiary)
```bash
aptos move run \
  --function-id '<ADDR>::vault::claim_tokens' \
  --args address:<VAULT_ADDR> \
  --assume-yes
```

### 5. Withdraw 2 APT
```bash
aptos move run \
  --function-id '<ADDR>::vault::withdraw_tokens' \
  --args address:<VAULT_ADDR> u64:200000000 \
  --assume-yes
```

### 6. Transfer Admin
```bash
aptos move run \
  --function-id '<ADDR>::vault::transfer_admin' \
  --args address:<VAULT_ADDR> address:<NEW_ADMIN_ADDR> \
  --assume-yes
```

### 7. Check Available Balance
```bash
aptos move view \
  --function-id '<ADDR>::vault::get_available_balance' \
  --args address:<VAULT_ADDR>
```

---

## 📡 Event System

| Event | Trigger | Key Fields |
|---|---|---|
| `VaultCreatedEvent` | `init_vault` | admin, timestamp |
| `DepositEvent` | `deposit_tokens` | admin, amount, new_balance, timestamp |
| `AllocateEvent` | `allocate_tokens` | admin, beneficiary, amount, timestamp |
| `ClaimEvent` | `claim_tokens` | beneficiary, amount, timestamp |
| `WithdrawEvent` | `withdraw_tokens` | admin, amount, remaining, timestamp |
| `AdminTransferredEvent` | `transfer_admin` | old_admin, new_admin, timestamp |

All events can be queried on [Aptos Explorer](https://explorer.aptoslabs.com) or via the Aptos GraphQL API.

---

## 🚨 Error Codes

| Code | Constant | Trigger |
|---|---|---|
| 1 | `E_NOT_ADMIN` | Caller is not vault admin |
| 2 | `E_VAULT_EXISTS` | Vault already initialized |
| 3 | `E_VAULT_NOT_FOUND` | No vault at given address |
| 4 | `E_INSUFFICIENT_BALANCE` | Not enough available funds |
| 5 | `E_ALREADY_CLAIMED` | Beneficiary already claimed |
| 6 | `E_NOT_ALLOCATED` | No allocation for beneficiary |
| 7 | `E_INVALID_AMOUNT` | Zero or negative amount |
| 8 | `E_INVALID_RECIPIENT` | Invalid beneficiary (0x0) |
| 9 | `E_INVALID_ADMIN` | Invalid new admin (0x0 or self) |
| 10 | `E_OVERFLOW` | Arithmetic overflow detected |

---

## ⛽ Gas Estimation

| Operation | Estimated Gas (Octas) | Estimated Cost (APT) |
|---|---|---|
| `init_vault` | ~2,000 | ~0.00002 |
| `deposit_tokens` | ~800 | ~0.000008 |
| `allocate_tokens` | ~1,000 | ~0.00001 |
| `claim_tokens` | ~900 | ~0.000009 |
| `withdraw_tokens` | ~800 | ~0.000008 |
| `transfer_admin` | ~700 | ~0.000007 |

> Estimates based on Aptos mainnet gas schedule v1. Actual costs may vary.

---

## 🛣️ Future Improvements

| Feature | Priority | Description |
|---|---|---|
| 🔓 **Multi-token support** | High | Support any Aptos fungible asset |
| ⏱️ **Time-locked allocations** | High | Beneficiary can only claim after a timestamp |
| 🔢 **Multi-admin (DAO)** | Medium | Governance-based admin with voting |
| 📦 **Batch allocations** | Medium | Allocate to multiple beneficiaries in one tx |
| 🤖 **AI-powered risk scoring** | Low | On-chain oracle for beneficiary risk assessment |
| 🔔 **Claim notifications** | Low | Event-driven off-chain notifications |
| 🌉 **Cross-chain bridge** | Future | Bridge vault funds across EVM chains |
| 🏛️ **Protocol fee** | Future | Optional protocol fee for vault operators |

---

## 📸 Screenshots


> **[<img width="1877" height="952" alt="Screenshot 2026-07-13 151209" src="https://github.com/user-attachments/assets/a8d8a548-97fd-4482-9b93-bae1ccb6276d" />
]**
>
> Recommended views:
> - Vault creation transaction
> - Deposit event log
> - Claim transaction
> - Explorer account view

---

## 📄 License

```
MIT License

Copyright (c) 2026 TrustFundX

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

<div align="center">

**Built with ❤️ on Aptos**

[Documentation](./deployment.md) • [Security](./security.md) • [Tests](./tests/)

</div>
