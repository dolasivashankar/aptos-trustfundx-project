# TrustFundX – Security Documentation

> Comprehensive security analysis, threat model, and best practices for the TrustFundX decentralized vault smart contract.

---

## Table of Contents

1. [Threat Model](#1-threat-model)
2. [Access Control](#2-access-control)
3. [Ownership Model](#3-ownership-model)
4. [Event Logging & Auditability](#4-event-logging--auditability)
5. [Replay Protection](#5-replay-protection)
6. [Overflow & Underflow Protection](#6-overflow--underflow-protection)
7. [Storage Safety](#7-storage-safety)
8. [Double-Claim Protection](#8-double-claim-protection)
9. [Input Validation](#9-input-validation)
10. [Upgrade Considerations](#10-upgrade-considerations)
11. [Known Limitations](#11-known-limitations)
12. [Best Practices Used](#12-best-practices-used)
13. [Security Error Reference](#13-security-error-reference)
14. [Audit Checklist](#14-audit-checklist)

---

## 1. Threat Model

### 1.1 Assets Under Protection

| Asset | Value | Risk Level |
|---|---|---|
| Deposited APT coins | High monetary value | 🔴 Critical |
| Admin key | Controls entire vault | 🔴 Critical |
| Allocation table | Defines who can claim | 🟡 High |
| Claim state | Prevents double-claiming | 🟡 High |
| Vault existence | Enables all operations | 🟢 Medium |

### 1.2 Threat Actors

| Actor | Capability | Motivation |
|---|---|---|
| **External Attacker** | Can call any public entry function | Steal vault funds |
| **Malicious Beneficiary** | Has a valid allocation | Double-claim or claim others' funds |
| **Compromised Admin Key** | Full admin privileges | Drain vault or redirect funds |
| **Rogue New Admin** | Admin after transfer | Revoke existing allocations |
| **Smart Contract Bug** | Internal logic flaw | State corruption or fund loss |

### 1.3 Attack Surface

```
External Surface:
  init_vault()         ← Restricted: can only create, not modify
  deposit_tokens()     ← Restricted: admin-only
  allocate_tokens()    ← Restricted: admin-only
  claim_tokens()       ← Public (but authorization via allocation table)
  withdraw_tokens()    ← Restricted: admin-only
  transfer_admin()     ← Restricted: admin-only

View Surface (read-only, no state change):
  get_admin()
  get_total_balance()
  get_available_balance()
  get_allocated_balance()
  get_claimable_balance()
  has_claimed()
  vault_exists()
```

---

## 2. Access Control

### 2.1 Admin Authorization

Every admin-restricted function uses the same verification pattern:

```move
assert!(
    vault.admin == signer::address_of(admin),
    E_NOT_ADMIN
);
```

**Why this is secure:**
- `signer::address_of()` is a Move primitive that cannot be spoofed
- The Aptos VM enforces that `&signer` references cannot be forged — only the actual account can produce its signer
- Comparing to `vault.admin` (stored on-chain) prevents any off-chain manipulation

### 2.2 Access Control Matrix

| Operation | Admin | Beneficiary | Anyone |
|---|---|---|---|
| `init_vault` | ✅ Own account only | ❌ | ❌ |
| `deposit_tokens` | ✅ | ❌ | ❌ |
| `allocate_tokens` | ✅ | ❌ | ❌ |
| `claim_tokens` | ❌ | ✅ Own allocation | ❌ |
| `withdraw_tokens` | ✅ | ❌ | ❌ |
| `transfer_admin` | ✅ | ❌ | ❌ |
| View functions | ✅ | ✅ | ✅ |

### 2.3 No Admin Self-Privilege on Claims

The admin **cannot** claim on behalf of a beneficiary. `claim_tokens` requires the beneficiary to be the transaction signer — the APT is deposited to `signer::address_of(beneficiary)`, not an admin-controlled address.

---

## 3. Ownership Model

### 3.1 Single-Owner Architecture

TrustFundX uses a single-owner admin model:
- Exactly one address is the vault admin at any time
- Admin identity is stored in the `Vault` resource: `vault.admin: address`
- Ownership is fully transferable but non-shareable

### 3.2 Ownership Transfer Security

The `transfer_admin` function enforces:

```move
// Cannot transfer to zero address (burns the vault)
assert!(new_admin != @0x0, E_INVALID_ADMIN);

// Cannot transfer to self (pointless, prevents misconfiguration)
assert!(new_admin != old_admin, E_INVALID_ADMIN);

// Cannot be called by non-admin
assert!(vault.admin == old_admin, E_NOT_ADMIN);
```

### 3.3 State Preservation After Transfer

When admin ownership is transferred:
- ✅ `vault.admin` is updated
- ✅ All balances remain unchanged
- ✅ All allocations remain active
- ✅ All claim records are preserved
- ✅ All event handles remain functional
- ❌ Old admin loses all privileges immediately

### 3.4 Key Compromise Mitigation

If an admin key is compromised:
1. A new account must be set up
2. The admin can call `transfer_admin` to the new key before the attacker does
3. **Recommendation**: Use a hardware wallet for admin keys in production

---

## 4. Event Logging & Auditability

### 4.1 Complete Event Coverage

Every state-modifying operation emits an event:

| Function | Event | Fields |
|---|---|---|
| `init_vault` | `VaultCreatedEvent` | admin, timestamp |
| `deposit_tokens` | `DepositEvent` | admin, amount, new_balance, timestamp |
| `allocate_tokens` | `AllocateEvent` | admin, beneficiary, amount, timestamp |
| `claim_tokens` | `ClaimEvent` | beneficiary, amount, timestamp |
| `withdraw_tokens` | `WithdrawEvent` | admin, amount, remaining, timestamp |
| `transfer_admin` | `AdminTransferredEvent` | old_admin, new_admin, timestamp |

### 4.2 Event Immutability

Aptos events are:
- **Immutable** once emitted — cannot be deleted or modified
- **Sequentially numbered** — gaps in sequence indicate failed transactions
- **Permanently stored** on-chain — full history is always available
- **Queryable** via Aptos GraphQL / REST API

### 4.3 Monitoring Recommendations

For production deployments, set up event monitoring for:
- Any `AdminTransferredEvent` (indicates ownership change)
- Large `WithdrawEvent` amounts (potential admin compromise)
- Unexpected `AllocateEvent` recipients
- Repeated failed transactions (potential attack attempts)

---

## 5. Replay Protection

### 5.1 Aptos-Level Protection

Aptos provides built-in replay protection at the VM level:
- Every transaction includes a **sequence number** that monotonically increases
- The VM rejects any transaction with a sequence number ≤ the account's current sequence number
- This prevents replay of signed transactions

### 5.2 Contract-Level Idempotency

At the contract level:
- `init_vault` is idempotent-safe: `assert!(!exists<Vault>(admin_addr), E_VAULT_EXISTS)`
- `claim_tokens` uses the `claimed` table to prevent re-execution
- Allocation and withdrawal are amount-checked, preventing draining via repeated calls

---

## 6. Overflow & Underflow Protection

### 6.1 Overflow Detection

```move
// Before adding to available_balance:
assert!(
    vault.available_balance <= (18446744073709551615u64 - amount),
    E_OVERFLOW
);
```

This checks that `available_balance + amount` will not exceed `u64::MAX`.

### 6.2 Underflow Prevention

Move does not have implicit underflow — arithmetic on `u64` that would go negative **aborts automatically** at the VM level. However, we add explicit guards before subtraction:

```move
// Before subtracting from available_balance:
assert!(vault.available_balance >= amount, E_INSUFFICIENT_BALANCE);
```

This provides a meaningful error code rather than a generic VM abort.

### 6.3 Balance Invariant

The following invariant is maintained after every operation:

```
coin::value(&vault.coin_store) == vault.available_balance + vault.allocated_balance
```

This is enforced by ensuring every deposit/withdraw/allocate/claim pair exactly mirrors coin movements with balance counter updates.

---

## 7. Storage Safety

### 7.1 Move Resource Model

TrustFundX leverages Move's **resource type system**:
- The `Vault` struct has the `key` ability — it can be stored globally
- Resources **cannot be copied or dropped accidentally** (no `copy` or `drop` ability)
- Resources must be explicitly moved into global storage with `move_to`
- Accessing a resource that doesn't exist causes an abort, not a null pointer

### 7.2 Table Safety

`aptos_std::table::Table` is used for allocation tracking:
- Tables use **off-chain key-value storage** with on-chain proofs
- Keys are hashed; values are accessed via Move borrow semantics
- `table::contains()` is always called before `table::borrow()` to prevent panics

### 7.3 Coin Store Safety

The `Coin<AptosCoin>` stored in the vault:
- Is a **zero-knowledge escrow** — no private key owns it; the smart contract controls it
- Can only be extracted via `coin::extract()` with explicit amount
- Cannot be transferred without an explicit `coin::deposit()` call

---

## 8. Double-Claim Protection

### 8.1 Claim State Machine

Each beneficiary goes through a one-way state machine:

```
[No Allocation] → [Allocated] → [Claimed]
                       ↑              |
                   allocate()      claim()
                                      ↓
                               [Cannot claim again]
```

### 8.2 Implementation

```move
// Check: has beneficiary claimed?
let already_claimed = table::contains(&vault.claimed, beneficiary_addr) &&
                      *table::borrow(&vault.claimed, beneficiary_addr);
assert!(!already_claimed, E_ALREADY_CLAIMED);

// After successful transfer:
// Mark as claimed — ONE WAY, irreversible
table::add(&mut vault.claimed, beneficiary_addr, true);
```

### 8.3 Claim Guard on Re-Allocation

The admin cannot re-allocate to a beneficiary who has already claimed:

```move
let has_claimed = table::contains(&vault.claimed, beneficiary) &&
                  *table::borrow(&vault.claimed, beneficiary);
assert!(!has_claimed, E_ALREADY_CLAIMED);
```

This prevents a pattern where:
1. Admin allocates 100 APT to Alice
2. Alice claims 100 APT
3. Admin re-allocates 100 APT to Alice (would create a second claim opportunity)

---

## 9. Input Validation

### 9.1 Amount Validation

All amount parameters are validated before use:
```move
assert!(amount > 0, E_INVALID_AMOUNT);
```

### 9.2 Address Validation

Beneficiary addresses:
```move
assert!(beneficiary != @0x0, E_INVALID_RECIPIENT);
```

New admin addresses:
```move
assert!(new_admin != @0x0, E_INVALID_ADMIN);
assert!(new_admin != old_admin, E_INVALID_ADMIN);
```

### 9.3 Vault Existence Validation

All functions validate vault existence before accessing:
```move
assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
```

This prevents accessing uninitialized memory and gives clear error messages.

---

## 10. Upgrade Considerations

### 10.1 Move's Upgrade Model

Aptos Move supports **compatible module upgrades** with restrictions:
- ✅ New public functions can be added
- ✅ New struct fields with defaults can be added (with `#[upgrade_policy = compatible]`)
- ❌ Existing function signatures cannot change
- ❌ Existing struct fields cannot be removed or reordered

### 10.2 Upgrade Policy

TrustFundX uses the default upgrade policy. To enable future upgrades:

```toml
# In Move.toml, add:
[package]
upgrade_policy = "compatible"
```

### 10.3 Recommended Upgrade Path

For breaking changes:
1. Deploy a new module version (e.g., `trustfundx_v2::vault`)
2. Implement a migration function in v2 that reads from v1's storage
3. Provide a time window for users to migrate
4. Announce deprecation of v1

### 10.4 Admin Key for Upgrades

Module upgrades require the **same account** that originally published the module. **Protect this key with extreme care**.

---

## 11. Known Limitations

| Limitation | Impact | Mitigation |
|---|---|---|
| Single admin model | Admin key loss = vault lock | Use hardware wallet; implement multi-sig in v2 |
| No time-locks | Admin can withdraw immediately | Future: `TimeLock` field per allocation |
| No multi-token support | Only handles APT | Future: Fungible Asset standard |
| No batch operations | One allocation per tx | Future: batch_allocate function |
| Admin can't access allocated funds | By design — protects beneficiaries | Intended behavior |
| No claim dispute mechanism | Allocations are final | Future: cancellation period |

---

## 12. Best Practices Used

### Move-Specific

| Practice | Implementation |
|---|---|
| ✅ No address derivation | All functions receive `vault_address` directly |
| ✅ Resource-based security | Vault is a `key` resource, not a map entry |
| ✅ Explicit signer verification | `signer::address_of()` used consistently |
| ✅ `acquires` annotation | All functions using `borrow_global` are annotated |
| ✅ Zero-copy borrows | `borrow_global_mut` used only when mutation is needed |
| ✅ `#[view]` annotation | All read-only functions marked as views |
| ✅ `#[test_only]` isolation | Test helpers cannot be called in production |

### General Smart Contract

| Practice | Implementation |
|---|---|
| ✅ Fail-fast validation | All inputs validated before state changes |
| ✅ Effects before interactions | State updated before coin transfers |
| ✅ Minimal trust surface | No external contract calls |
| ✅ Event-driven audit trail | All mutations emit events |
| ✅ Meaningful error codes | 10 distinct error constants |
| ✅ Guard clauses | All preconditions checked at function entry |

---

## 13. Security Error Reference

| Code | Constant | Trigger Condition | Recommended Action |
|---|---|---|---|
| 1 | `E_NOT_ADMIN` | Non-admin called admin function | Verify you are using the correct wallet |
| 2 | `E_VAULT_EXISTS` | `init_vault` called twice | Vault already created; no action needed |
| 3 | `E_VAULT_NOT_FOUND` | No vault at given address | Call `init_vault` first; verify address |
| 4 | `E_INSUFFICIENT_BALANCE` | Balance too low | Deposit more APT before allocating/withdrawing |
| 5 | `E_ALREADY_CLAIMED` | Beneficiary trying to double-claim | Already received funds; nothing to do |
| 6 | `E_NOT_ALLOCATED` | Beneficiary has no allocation | Contact vault admin to allocate |
| 7 | `E_INVALID_AMOUNT` | Zero amount provided | Use amount > 0 |
| 8 | `E_INVALID_RECIPIENT` | Beneficiary is 0x0 | Provide a valid beneficiary address |
| 9 | `E_INVALID_ADMIN` | New admin is 0x0 or self | Provide a different, valid new admin address |
| 10 | `E_OVERFLOW` | Balance would overflow u64 | Amount too large; reduce deposit size |

---

## 14. Audit Checklist

Use this checklist before production deployment:

### Pre-Deployment

- [ ] All 25 unit tests pass: `aptos move test`
- [ ] No compiler warnings: `aptos move compile`
- [ ] Move.toml address is correct
- [ ] Admin wallet is a hardware wallet or multi-sig
- [ ] Contract source code is publicly available on GitHub
- [ ] Events are being indexed (set up Aptos indexer or use a third-party)

### Post-Deployment

- [ ] `init_vault` transaction confirmed on explorer
- [ ] All 6 event types visible in explorer after test transactions
- [ ] View functions return correct values
- [ ] `vault_exists` returns `true` for your address
- [ ] Admin address is correct via `get_admin()`
- [ ] Set up event monitoring for admin transfers

### Ongoing

- [ ] Monitor `AdminTransferredEvent` for unauthorized ownership changes
- [ ] Monitor large withdrawals
- [ ] Keep admin private key in cold storage
- [ ] Review beneficiary addresses before allocation
- [ ] Have an incident response plan for key compromise

---

*This security documentation should be reviewed and updated with every contract upgrade.*

*For security disclosures, contact the TrustFundX team via GitHub Security Advisories.*
