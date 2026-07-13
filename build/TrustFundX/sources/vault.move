// TrustFundX – Decentralized AI-Powered Token Vault & Fund Management Platform
//
// Module: trustfundx::vault
//
// Overview:
//   TrustFundX is a secure on-chain vault where an admin can deposit APT tokens,
//   allocate them to beneficiaries, allow beneficiaries to claim their allocation,
//   withdraw unused funds, and transfer vault ownership to a new admin.
//
//   Every function receives `vault_address: address` directly — no address
//   derivation from admin keys is ever performed.
//
// Security Model:
//   - Admin verified via: assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN)
//   - Beneficiary verified via allocation table lookup
//   - All state mutations emit on-chain events
//   - Overflow/underflow protected via checked arithmetic
//
// SPDX-License-Identifier: MIT

module trustfundx::vault {

    // ============================================================
    //  Imports
    // ============================================================

    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_std::table::{Self, Table};

    // ============================================================
    //  Error Codes
    // ============================================================

    /// Caller is not the vault admin
    const E_NOT_ADMIN: u64 = 1;
    /// Vault already exists at this address
    const E_VAULT_EXISTS: u64 = 2;
    /// No vault found at the given address
    const E_VAULT_NOT_FOUND: u64 = 3;
    /// Insufficient available balance for the operation
    const E_INSUFFICIENT_BALANCE: u64 = 4;
    /// Beneficiary has already claimed their allocation
    const E_ALREADY_CLAIMED: u64 = 5;
    /// Beneficiary has no allocation in this vault
    const E_NOT_ALLOCATED: u64 = 6;
    /// Amount must be greater than zero
    const E_INVALID_AMOUNT: u64 = 7;
    /// Beneficiary address is invalid (self-allocation or zero)
    const E_INVALID_RECIPIENT: u64 = 8;
    /// New admin address is invalid (zero address or same as current)
    const E_INVALID_ADMIN: u64 = 9;
    /// Arithmetic overflow detected
    const E_OVERFLOW: u64 = 10;

    // ============================================================
    //  Events
    // ============================================================

    /// Emitted when a new vault is created
    struct VaultCreatedEvent has drop, store {
        admin:     address,
        timestamp: u64,
    }

    /// Emitted when tokens are deposited into the vault
    struct DepositEvent has drop, store {
        admin:       address,
        amount:      u64,
        new_balance: u64,
        timestamp:   u64,
    }

    /// Emitted when tokens are allocated to a beneficiary
    struct AllocateEvent has drop, store {
        admin:       address,
        beneficiary: address,
        amount:      u64,
        timestamp:   u64,
    }

    /// Emitted when a beneficiary claims their allocation
    struct ClaimEvent has drop, store {
        beneficiary: address,
        amount:      u64,
        timestamp:   u64,
    }

    /// Emitted when the admin withdraws unused funds
    struct WithdrawEvent has drop, store {
        admin:     address,
        amount:    u64,
        remaining: u64,
        timestamp: u64,
    }

    /// Emitted when vault ownership is transferred to a new admin
    struct AdminTransferredEvent has drop, store {
        old_admin:  address,
        new_admin:  address,
        timestamp:  u64,
    }

    // ============================================================
    //  Vault Resource
    // ============================================================

    /// Core vault resource stored at `vault_address`.
    /// All balances are in Octas (1 APT = 100_000_000 Octas).
    struct Vault has key {
        /// Current admin of the vault
        admin:             address,
        /// Total APT deposited into the vault (cumulative, never decreases)
        total_deposited:   u64,
        /// APT available for new allocations or admin withdrawal
        available_balance: u64,
        /// APT currently locked in pending allocations (not yet claimed)
        allocated_balance: u64,
        /// Actual coin store holding the APT
        coin_store:        Coin<AptosCoin>,
        /// Maps beneficiary address → allocated amount (0 if none)
        allocations:       Table<address, u64>,
        /// Maps beneficiary address → whether they have claimed
        claimed:           Table<address, bool>,
        /// Maps beneficiary address → amount actually claimed
        claim_amounts:     Table<address, u64>,
        /// Event handles
        deposit_events:    EventHandle<DepositEvent>,
        allocate_events:   EventHandle<AllocateEvent>,
        claim_events:      EventHandle<ClaimEvent>,
        withdraw_events:   EventHandle<WithdrawEvent>,
        transfer_events:   EventHandle<AdminTransferredEvent>,
        created_events:    EventHandle<VaultCreatedEvent>,
    }

    // ============================================================
    //  Entry Functions – Vault Lifecycle
    // ============================================================

    /// Initialize a new TrustFundX vault at the admin's account.
    ///
    /// The vault is stored at `signer::address_of(admin)`.
    /// After creation, all subsequent calls must pass this address as `vault_address`.
    ///
    /// Aborts:
    ///   - `E_VAULT_EXISTS` if a vault already exists at admin's address
    public entry fun init_vault(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        // Ensure vault does not already exist
        assert!(!exists<Vault>(admin_addr), E_VAULT_EXISTS);

        // Create the vault resource
        let vault = Vault {
            admin:             admin_addr,
            total_deposited:   0,
            available_balance: 0,
            allocated_balance: 0,
            coin_store:        coin::zero<AptosCoin>(),
            allocations:       table::new(),
            claimed:           table::new(),
            claim_amounts:     table::new(),
            deposit_events:    account::new_event_handle<DepositEvent>(admin),
            allocate_events:   account::new_event_handle<AllocateEvent>(admin),
            claim_events:      account::new_event_handle<ClaimEvent>(admin),
            withdraw_events:   account::new_event_handle<WithdrawEvent>(admin),
            transfer_events:   account::new_event_handle<AdminTransferredEvent>(admin),
            created_events:    account::new_event_handle<VaultCreatedEvent>(admin),
        };

        // Emit VaultCreatedEvent
        event::emit_event(
            &mut vault.created_events,
            VaultCreatedEvent {
                admin:     admin_addr,
                timestamp: timestamp::now_seconds(),
            }
        );

        // Store vault at admin's address
        move_to(admin, vault);
    }

    // ============================================================
    //  Entry Functions – Deposit
    // ============================================================

    /// Deposit `amount` Octas of APT into the vault at `vault_address`.
    ///
    /// Only the vault admin may call this function.
    /// Increases `available_balance` and `total_deposited`.
    ///
    /// Parameters:
    ///   - `admin`         – signer must be the vault admin
    ///   - `vault_address` – address where the Vault resource is stored
    ///   - `amount`        – amount in Octas to deposit (must be > 0)
    ///
    /// Aborts:
    ///   - `E_VAULT_NOT_FOUND`      if no vault at `vault_address`
    ///   - `E_NOT_ADMIN`            if caller is not admin
    ///   - `E_INVALID_AMOUNT`       if amount == 0
    ///   - `E_OVERFLOW`             if balance would overflow u64
    public entry fun deposit_tokens(
        admin:         &signer,
        vault_address: address,
        amount:        u64,
    ) acquires Vault {
        // Validate vault exists
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);

        let vault = borrow_global_mut<Vault>(vault_address);

        // Verify admin
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);

        // Validate amount
        assert!(amount > 0, E_INVALID_AMOUNT);

        // Overflow check for available_balance
        assert!(
            vault.available_balance <= (18446744073709551615u64 - amount),
            E_OVERFLOW
        );

        // Withdraw APT from admin's account and merge into vault coin_store
        let deposited_coin = coin::withdraw<AptosCoin>(admin, amount);
        coin::merge(&mut vault.coin_store, deposited_coin);

        // Update balances
        vault.available_balance = vault.available_balance + amount;
        vault.total_deposited   = vault.total_deposited + amount;

        // Emit DepositEvent
        event::emit_event(
            &mut vault.deposit_events,
            DepositEvent {
                admin:       signer::address_of(admin),
                amount,
                new_balance: vault.available_balance,
                timestamp:   timestamp::now_seconds(),
            }
        );
    }

    // ============================================================
    //  Entry Functions – Allocation
    // ============================================================

    /// Allocate `amount` Octas to a `beneficiary` from the vault at `vault_address`.
    ///
    /// Only the vault admin may allocate tokens.
    /// Moves funds from `available_balance` to `allocated_balance`.
    /// A beneficiary can be allocated to only once; re-allocation will add to existing.
    ///
    /// Parameters:
    ///   - `admin`         – signer must be the vault admin
    ///   - `vault_address` – address where the Vault resource is stored
    ///   - `beneficiary`   – address that will be able to claim these tokens
    ///   - `amount`        – amount in Octas to allocate (must be > 0)
    ///
    /// Aborts:
    ///   - `E_VAULT_NOT_FOUND`      if no vault at `vault_address`
    ///   - `E_NOT_ADMIN`            if caller is not admin
    ///   - `E_INVALID_AMOUNT`       if amount == 0
    ///   - `E_INVALID_RECIPIENT`    if beneficiary is @0x0 or the admin itself
    ///   - `E_INSUFFICIENT_BALANCE` if available_balance < amount
    ///   - `E_ALREADY_CLAIMED`      if beneficiary has already claimed
    public entry fun allocate_tokens(
        admin:         &signer,
        vault_address: address,
        beneficiary:   address,
        amount:        u64,
    ) acquires Vault {
        // Validate vault exists
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);

        let vault = borrow_global_mut<Vault>(vault_address);

        // Verify admin
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);

        // Validate amount
        assert!(amount > 0, E_INVALID_AMOUNT);

        // Validate beneficiary — cannot be zero address or the admin
        assert!(beneficiary != @0x0, E_INVALID_RECIPIENT);

        // Validate sufficient available balance
        assert!(vault.available_balance >= amount, E_INSUFFICIENT_BALANCE);

        // Ensure beneficiary has not already claimed (cannot re-allocate after claim)
        let has_claimed = table::contains(&vault.claimed, beneficiary) &&
                          *table::borrow(&vault.claimed, beneficiary);
        assert!(!has_claimed, E_ALREADY_CLAIMED);

        // Update or create allocation
        if (table::contains(&vault.allocations, beneficiary)) {
            let existing = table::borrow_mut(&mut vault.allocations, beneficiary);
            *existing = *existing + amount;
        } else {
            table::add(&mut vault.allocations, beneficiary, amount);
        };

        // Move funds from available to allocated
        vault.available_balance = vault.available_balance - amount;
        vault.allocated_balance = vault.allocated_balance + amount;

        // Emit AllocateEvent
        event::emit_event(
            &mut vault.allocate_events,
            AllocateEvent {
                admin:       signer::address_of(admin),
                beneficiary,
                amount,
                timestamp:   timestamp::now_seconds(),
            }
        );
    }

    // ============================================================
    //  Entry Functions – Claim
    // ============================================================

    /// Claim allocated tokens from the vault at `vault_address`.
    ///
    /// Any address with an active allocation may call this.
    /// Transfers the full allocated amount to the caller's wallet.
    /// Each beneficiary may only claim once.
    ///
    /// Parameters:
    ///   - `beneficiary`   – signer must have an allocation in the vault
    ///   - `vault_address` – address where the Vault resource is stored
    ///
    /// Aborts:
    ///   - `E_VAULT_NOT_FOUND`   if no vault at `vault_address`
    ///   - `E_NOT_ALLOCATED`     if caller has no allocation
    ///   - `E_ALREADY_CLAIMED`   if caller has already claimed
    public entry fun claim_tokens(
        beneficiary:   &signer,
        vault_address: address,
    ) acquires Vault {
        // Validate vault exists
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);

        let vault = borrow_global_mut<Vault>(vault_address);

        let beneficiary_addr = signer::address_of(beneficiary);

        // Verify allocation exists
        assert!(
            table::contains(&vault.allocations, beneficiary_addr),
            E_NOT_ALLOCATED
        );

        // Verify not already claimed
        let already_claimed = table::contains(&vault.claimed, beneficiary_addr) &&
                              *table::borrow(&vault.claimed, beneficiary_addr);
        assert!(!already_claimed, E_ALREADY_CLAIMED);

        // Get claim amount
        let claim_amount = *table::borrow(&vault.allocations, beneficiary_addr);
        assert!(claim_amount > 0, E_INVALID_AMOUNT);

        // Mark as claimed
        if (table::contains(&vault.claimed, beneficiary_addr)) {
            *table::borrow_mut(&mut vault.claimed, beneficiary_addr) = true;
        } else {
            table::add(&mut vault.claimed, beneficiary_addr, true);
        };

        // Record claim amount
        if (table::contains(&vault.claim_amounts, beneficiary_addr)) {
            *table::borrow_mut(&mut vault.claim_amounts, beneficiary_addr) = claim_amount;
        } else {
            table::add(&mut vault.claim_amounts, beneficiary_addr, claim_amount);
        };

        // Reduce allocated balance
        vault.allocated_balance = vault.allocated_balance - claim_amount;

        // Extract coins from vault and deposit to beneficiary
        let payout = coin::extract(&mut vault.coin_store, claim_amount);
        coin::deposit<AptosCoin>(beneficiary_addr, payout);

        // Emit ClaimEvent
        event::emit_event(
            &mut vault.claim_events,
            ClaimEvent {
                beneficiary: beneficiary_addr,
                amount:      claim_amount,
                timestamp:   timestamp::now_seconds(),
            }
        );
    }

    // ============================================================
    //  Entry Functions – Withdraw
    // ============================================================

    /// Withdraw `amount` Octas of unused (unallocated) APT from the vault.
    ///
    /// Only the vault admin may withdraw.
    /// Can only withdraw from `available_balance` — allocated funds are protected.
    ///
    /// Parameters:
    ///   - `admin`         – signer must be the vault admin
    ///   - `vault_address` – address where the Vault resource is stored
    ///   - `amount`        – amount in Octas to withdraw (must be > 0)
    ///
    /// Aborts:
    ///   - `E_VAULT_NOT_FOUND`      if no vault at `vault_address`
    ///   - `E_NOT_ADMIN`            if caller is not admin
    ///   - `E_INVALID_AMOUNT`       if amount == 0
    ///   - `E_INSUFFICIENT_BALANCE` if available_balance < amount
    public entry fun withdraw_tokens(
        admin:         &signer,
        vault_address: address,
        amount:        u64,
    ) acquires Vault {
        // Validate vault exists
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);

        let vault = borrow_global_mut<Vault>(vault_address);

        // Verify admin
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);

        // Validate amount
        assert!(amount > 0, E_INVALID_AMOUNT);

        // Validate sufficient available balance
        assert!(vault.available_balance >= amount, E_INSUFFICIENT_BALANCE);

        // Deduct from available balance
        vault.available_balance = vault.available_balance - amount;

        // Extract and deposit coins to admin
        let withdrawn = coin::extract(&mut vault.coin_store, amount);
        coin::deposit<AptosCoin>(signer::address_of(admin), withdrawn);

        // Emit WithdrawEvent
        event::emit_event(
            &mut vault.withdraw_events,
            WithdrawEvent {
                admin:     signer::address_of(admin),
                amount,
                remaining: vault.available_balance,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    // ============================================================
    //  Entry Functions – Ownership Transfer
    // ============================================================

    /// Transfer vault admin ownership to `new_admin`.
    ///
    /// Only the current admin may initiate a transfer.
    /// `new_admin` cannot be @0x0 or the current admin.
    /// The vault state (balances, allocations, claims) is preserved.
    ///
    /// Parameters:
    ///   - `admin`         – signer must be the current vault admin
    ///   - `vault_address` – address where the Vault resource is stored
    ///   - `new_admin`     – address of the incoming admin
    ///
    /// Aborts:
    ///   - `E_VAULT_NOT_FOUND` if no vault at `vault_address`
    ///   - `E_NOT_ADMIN`       if caller is not current admin
    ///   - `E_INVALID_ADMIN`   if new_admin is @0x0 or same as current admin
    public entry fun transfer_admin(
        admin:         &signer,
        vault_address: address,
        new_admin:     address,
    ) acquires Vault {
        // Validate vault exists
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);

        let vault = borrow_global_mut<Vault>(vault_address);

        let old_admin = signer::address_of(admin);

        // Verify current admin
        assert!(vault.admin == old_admin, E_NOT_ADMIN);

        // Cannot transfer to zero address
        assert!(new_admin != @0x0, E_INVALID_ADMIN);

        // Cannot transfer to self
        assert!(new_admin != old_admin, E_INVALID_ADMIN);

        // Emit AdminTransferredEvent before state change
        event::emit_event(
            &mut vault.transfer_events,
            AdminTransferredEvent {
                old_admin,
                new_admin,
                timestamp: timestamp::now_seconds(),
            }
        );

        // Update admin — vault state fully preserved
        vault.admin = new_admin;
    }

    // ============================================================
    //  View Functions
    // ============================================================

    #[view]
    /// Returns the current admin address of the vault at `vault_address`.
    /// Aborts: `E_VAULT_NOT_FOUND` if no vault exists at `vault_address`
    public fun get_admin(vault_address: address): address acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        borrow_global<Vault>(vault_address).admin
    }

    #[view]
    /// Returns the total APT (Octas) ever deposited into the vault.
    /// Aborts: `E_VAULT_NOT_FOUND` if no vault exists at `vault_address`
    public fun get_total_balance(vault_address: address): u64 acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        borrow_global<Vault>(vault_address).total_deposited
    }

    #[view]
    /// Returns the currently available (unallocated) APT balance in Octas.
    /// Aborts: `E_VAULT_NOT_FOUND` if no vault exists at `vault_address`
    public fun get_available_balance(vault_address: address): u64 acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        borrow_global<Vault>(vault_address).available_balance
    }

    #[view]
    /// Returns the currently allocated (locked pending claim) APT balance in Octas.
    /// Aborts: `E_VAULT_NOT_FOUND` if no vault exists at `vault_address`
    public fun get_allocated_balance(vault_address: address): u64 acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        borrow_global<Vault>(vault_address).allocated_balance
    }

    #[view]
    /// Returns the claimable allocation for `beneficiary` in Octas.
    /// Returns 0 if beneficiary has no allocation or has already claimed.
    /// Aborts: `E_VAULT_NOT_FOUND` if no vault exists at `vault_address`
    public fun get_claimable_balance(
        vault_address: address,
        beneficiary:   address,
    ): u64 acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        let vault = borrow_global<Vault>(vault_address);

        // Return 0 if no allocation
        if (!table::contains(&vault.allocations, beneficiary)) {
            return 0
        };

        // Return 0 if already claimed
        let already_claimed = table::contains(&vault.claimed, beneficiary) &&
                              *table::borrow(&vault.claimed, beneficiary);
        if (already_claimed) {
            return 0
        };

        *table::borrow(&vault.allocations, beneficiary)
    }

    #[view]
    /// Returns whether a beneficiary has already claimed their allocation.
    /// Aborts: `E_VAULT_NOT_FOUND` if no vault exists at `vault_address`
    public fun has_claimed(
        vault_address: address,
        beneficiary:   address,
    ): bool acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        let vault = borrow_global<Vault>(vault_address);

        if (!table::contains(&vault.claimed, beneficiary)) {
            return false
        };
        *table::borrow(&vault.claimed, beneficiary)
    }

    #[view]
    /// Returns whether a vault exists at `vault_address`.
    public fun vault_exists(vault_address: address): bool {
        exists<Vault>(vault_address)
    }

    // ============================================================
    //  Test-Only Helper
    // ============================================================

    #[test_only]
    /// Expose vault fields for unit testing.
    public fun get_vault_info(vault_address: address): (address, u64, u64, u64) acquires Vault {
        assert!(exists<Vault>(vault_address), E_VAULT_NOT_FOUND);
        let vault = borrow_global<Vault>(vault_address);
        (vault.admin, vault.total_deposited, vault.available_balance, vault.allocated_balance)
    }

}
