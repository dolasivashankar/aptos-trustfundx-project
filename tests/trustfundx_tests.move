// TrustFundX – Unit Tests
//
// Root cause of all failures: coin::register<AptosCoin> requires AptosCoin to be
// initialized (via initialize_for_test) BEFORE any account registers for it.
// Rewritten: every test calls init_env() first which publishes CoinInfo,
// then uses new_account() with the MintCapability to fund accounts.
//
// Run with: aptos move test

#[test_only]
module trustfundx::vault_tests {

    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use trustfundx::vault;

    // ============================================================
    //  Test Helpers
    // ============================================================

    /// Initialize the Aptos test environment.
    /// - Creates the @aptos_framework account
    /// - Starts the timestamp module
    /// - Publishes AptosCoin CoinInfo so coin::register works
    /// Returns (BurnCapability, MintCapability) — caller MUST destroy both at end.
    fun init_env(
        aptos: &signer,
    ): (coin::BurnCapability<AptosCoin>, coin::MintCapability<AptosCoin>) {
        account::create_account_for_test(signer::address_of(aptos));
        timestamp::set_time_has_started_for_testing(aptos);
        aptos_framework::aptos_coin::initialize_for_test(aptos)
    }

    /// Create a test account, register it for AptosCoin, and fund it.
    /// `amount` may be 0 if no initial balance is needed.
    fun new_account(
        mint_cap: &coin::MintCapability<AptosCoin>,
        user:     &signer,
        amount:   u64,
    ) {
        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
        if (amount > 0) {
            let coins = coin::mint<AptosCoin>(amount, mint_cap);
            coin::deposit(signer::address_of(user), coins);
        };
    }

    // ============================================================
    //  Test 1: Vault Initialization
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    public fun test_init_vault(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 0);

        // Vault should not exist before init
        assert!(!vault::vault_exists(signer::address_of(admin)), 0);

        vault::init_vault(admin);

        // Vault should exist after init
        assert!(vault::vault_exists(signer::address_of(admin)), 1);

        // Verify initial state
        let (admin_addr, total, available, allocated) =
            vault::get_vault_info(signer::address_of(admin));
        assert!(admin_addr == signer::address_of(admin), 2);
        assert!(total     == 0, 3);
        assert!(available == 0, 4);
        assert!(allocated == 0, 5);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 2: Double Initialization Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 2, location = trustfundx::vault)]
    public fun test_double_init_vault(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 0);

        vault::init_vault(admin);
        vault::init_vault(admin); // E_VAULT_EXISTS = 2

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 3: Deposit Tokens
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    public fun test_deposit(aptos: &signer, admin: &signer) {
        let deposit_amount = 1_000_000_000u64;
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, deposit_amount * 2);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, deposit_amount);

        let (_, total, available, allocated) = vault::get_vault_info(vault_address);
        assert!(total     == deposit_amount, 0);
        assert!(available == deposit_amount, 1);
        assert!(allocated == 0,             2);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 4: Zero Deposit Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 7, location = trustfundx::vault)]
    public fun test_zero_deposit(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 1_000_000_000u64);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 0); // E_INVALID_AMOUNT = 7

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 5: Unauthorized Deposit Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, attacker = @0xBEEF)]
    #[expected_failure(abort_code = 1, location = trustfundx::vault)]
    public fun test_unauthorized_deposit(
        aptos:    &signer,
        admin:    &signer,
        attacker: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,    1_000_000_000u64);
        new_account(&mint, attacker, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(attacker, vault_address, 500_000_000u64); // E_NOT_ADMIN = 1

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 6: Allocate Tokens
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, beneficiary = @0xABCD)]
    public fun test_allocate(
        aptos:       &signer,
        admin:       &signer,
        beneficiary: &signer,
    ) {
        let deposit_amount = 1_000_000_000u64;
        let alloc_amount   = 300_000_000u64;

        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       deposit_amount * 2);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, deposit_amount);
        vault::allocate_tokens(admin, vault_address, signer::address_of(beneficiary), alloc_amount);

        let (_, _, available, allocated) = vault::get_vault_info(vault_address);
        assert!(available == deposit_amount - alloc_amount, 0);
        assert!(allocated == alloc_amount,                 1);

        let claimable = vault::get_claimable_balance(vault_address, signer::address_of(beneficiary));
        assert!(claimable == alloc_amount, 2);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 7: Allocate Zero Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, beneficiary = @0xABCD)]
    #[expected_failure(abort_code = 7, location = trustfundx::vault)]
    public fun test_zero_allocate(
        aptos:       &signer,
        admin:       &signer,
        beneficiary: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       1_000_000_000u64);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);
        vault::allocate_tokens(admin, vault_address, signer::address_of(beneficiary), 0); // E_INVALID_AMOUNT = 7

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 8: Allocate to 0x0 Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 8, location = trustfundx::vault)]
    public fun test_allocate_invalid_recipient(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 1_000_000_000u64);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);
        vault::allocate_tokens(admin, vault_address, @0x0, 100_000_000u64); // E_INVALID_RECIPIENT = 8

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 9: Over-Allocation Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, beneficiary = @0xABCD)]
    #[expected_failure(abort_code = 4, location = trustfundx::vault)]
    public fun test_insufficient_balance_for_allocation(
        aptos:       &signer,
        admin:       &signer,
        beneficiary: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       1_000_000_000u64);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 100_000_000u64);
        // Try to allocate more than deposited — E_INSUFFICIENT_BALANCE = 4
        vault::allocate_tokens(admin, vault_address, signer::address_of(beneficiary), 500_000_000u64);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 10: Unauthorized Allocate Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, attacker = @0xBEEF, beneficiary = @0xABCD)]
    #[expected_failure(abort_code = 1, location = trustfundx::vault)]
    public fun test_unauthorized_allocate(
        aptos:       &signer,
        admin:       &signer,
        attacker:    &signer,
        beneficiary: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       1_000_000_000u64);
        new_account(&mint, attacker,    0);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);
        vault::allocate_tokens(attacker, vault_address, signer::address_of(beneficiary), 100_000_000u64); // E_NOT_ADMIN = 1

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 11: Claim Tokens
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, beneficiary = @0xABCD)]
    public fun test_claim(
        aptos:       &signer,
        admin:       &signer,
        beneficiary: &signer,
    ) {
        let deposit_amount = 1_000_000_000u64;
        let alloc_amount   = 300_000_000u64;

        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       deposit_amount * 2);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address       = signer::address_of(admin);
        let beneficiary_address = signer::address_of(beneficiary);

        vault::deposit_tokens(admin, vault_address, deposit_amount);
        vault::allocate_tokens(admin, vault_address, beneficiary_address, alloc_amount);

        // Pre-claim: has_claimed should be false
        assert!(!vault::has_claimed(vault_address, beneficiary_address), 0);

        vault::claim_tokens(beneficiary, vault_address);

        // Post-claim: has_claimed should be true
        assert!(vault::has_claimed(vault_address, beneficiary_address), 1);

        // Claimable balance should now be 0
        let claimable = vault::get_claimable_balance(vault_address, beneficiary_address);
        assert!(claimable == 0, 2);

        // Beneficiary's coin balance should equal alloc_amount
        let balance = coin::balance<AptosCoin>(beneficiary_address);
        assert!(balance == alloc_amount, 3);

        // Vault allocated balance should be zero
        let (_, _, _, allocated) = vault::get_vault_info(vault_address);
        assert!(allocated == 0, 4);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 12: Double Claim Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, beneficiary = @0xABCD)]
    #[expected_failure(abort_code = 5, location = trustfundx::vault)]
    public fun test_double_claim(
        aptos:       &signer,
        admin:       &signer,
        beneficiary: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       1_000_000_000u64);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);
        vault::allocate_tokens(admin, vault_address, signer::address_of(beneficiary), 100_000_000u64);
        vault::claim_tokens(beneficiary, vault_address);
        vault::claim_tokens(beneficiary, vault_address); // E_ALREADY_CLAIMED = 5

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 13: Claim Without Allocation Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, beneficiary = @0xABCD)]
    #[expected_failure(abort_code = 6, location = trustfundx::vault)]
    public fun test_claim_without_allocation(
        aptos:       &signer,
        admin:       &signer,
        beneficiary: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,       1_000_000_000u64);
        new_account(&mint, beneficiary, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);
        // No allocation — claim should abort with E_NOT_ALLOCATED = 6
        vault::claim_tokens(beneficiary, vault_address);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 14: Withdraw Tokens
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    public fun test_withdraw(aptos: &signer, admin: &signer) {
        let deposit_amount  = 1_000_000_000u64;
        let withdraw_amount = 400_000_000u64;

        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, deposit_amount * 2);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, deposit_amount);

        let balance_before = coin::balance<AptosCoin>(signer::address_of(admin));
        vault::withdraw_tokens(admin, vault_address, withdraw_amount);
        let balance_after = coin::balance<AptosCoin>(signer::address_of(admin));

        // Admin wallet should increase by withdraw_amount
        assert!(balance_after == balance_before + withdraw_amount, 0);

        // Vault available_balance should decrease
        let (_, _, available, _) = vault::get_vault_info(vault_address);
        assert!(available == deposit_amount - withdraw_amount, 1);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 15: Withdraw More Than Available Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 4, location = trustfundx::vault)]
    public fun test_withdraw_insufficient(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 1_000_000_000u64);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 100_000_000u64);
        vault::withdraw_tokens(admin, vault_address, 500_000_000u64); // E_INSUFFICIENT_BALANCE = 4

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 16: Unauthorized Withdraw Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, attacker = @0xBEEF)]
    #[expected_failure(abort_code = 1, location = trustfundx::vault)]
    public fun test_unauthorized_withdraw(
        aptos:    &signer,
        admin:    &signer,
        attacker: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,    1_000_000_000u64);
        new_account(&mint, attacker, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);
        vault::withdraw_tokens(attacker, vault_address, 100_000_000u64); // E_NOT_ADMIN = 1

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 17: Invalid Vault Address Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 3, location = trustfundx::vault)]
    public fun test_invalid_vault(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 1_000_000_000u64);
        // No vault initialized — deposit should abort with E_VAULT_NOT_FOUND = 3
        vault::deposit_tokens(admin, @0xDEAD, 100_000_000u64);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 18: Transfer Admin
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, new_admin = @0xDEAD)]
    public fun test_transfer_admin(
        aptos:     &signer,
        admin:     &signer,
        new_admin: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,     1_000_000_000u64);
        new_account(&mint, new_admin, 0);
        vault::init_vault(admin);

        let vault_address     = signer::address_of(admin);
        let new_admin_address = signer::address_of(new_admin);

        vault::transfer_admin(admin, vault_address, new_admin_address);

        // Vault admin should now be new_admin
        let current_admin = vault::get_admin(vault_address);
        assert!(current_admin == new_admin_address, 0);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 19: New Admin Can Deposit After Transfer
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, new_admin = @0xDEAD)]
    public fun test_new_admin_permissions(
        aptos:     &signer,
        admin:     &signer,
        new_admin: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,     1_000_000_000u64);
        new_account(&mint, new_admin, 500_000_000u64);
        vault::init_vault(admin);

        let vault_address     = signer::address_of(admin);
        let new_admin_address = signer::address_of(new_admin);

        vault::transfer_admin(admin, vault_address, new_admin_address);

        // New admin should be able to deposit
        vault::deposit_tokens(new_admin, vault_address, 100_000_000u64);

        let (_, total, available, _) = vault::get_vault_info(vault_address);
        assert!(total     == 100_000_000u64, 0);
        assert!(available == 100_000_000u64, 1);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 20: Old Admin Cannot Operate After Transfer
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, new_admin = @0xDEAD)]
    #[expected_failure(abort_code = 1, location = trustfundx::vault)]
    public fun test_old_admin_revoked(
        aptos:     &signer,
        admin:     &signer,
        new_admin: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,     1_000_000_000u64);
        new_account(&mint, new_admin, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::transfer_admin(admin, vault_address, signer::address_of(new_admin));

        // Old admin tries to deposit — E_NOT_ADMIN = 1
        vault::deposit_tokens(admin, vault_address, 100_000_000u64);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 21: Transfer to 0x0 Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 9, location = trustfundx::vault)]
    public fun test_transfer_to_zero(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::transfer_admin(admin, vault_address, @0x0); // E_INVALID_ADMIN = 9

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 22: Transfer to Self Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    #[expected_failure(abort_code = 9, location = trustfundx::vault)]
    public fun test_transfer_to_self(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::transfer_admin(admin, vault_address, signer::address_of(admin)); // E_INVALID_ADMIN = 9

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 23: Unauthorized Transfer Should Fail
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, attacker = @0xBEEF)]
    #[expected_failure(abort_code = 1, location = trustfundx::vault)]
    public fun test_unauthorized_transfer(
        aptos:    &signer,
        admin:    &signer,
        attacker: &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin,    0);
        new_account(&mint, attacker, 0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::transfer_admin(attacker, vault_address, signer::address_of(attacker)); // E_NOT_ADMIN = 1

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 24: Multiple Deposits Accumulate
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE)]
    public fun test_multiple_deposits(aptos: &signer, admin: &signer) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 5_000_000_000u64);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 1_000_000_000u64);
        vault::deposit_tokens(admin, vault_address, 2_000_000_000u64);
        vault::deposit_tokens(admin, vault_address, 500_000_000u64);

        let (_, total, available, _) = vault::get_vault_info(vault_address);
        assert!(total     == 3_500_000_000u64, 0);
        assert!(available == 3_500_000_000u64, 1);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    // ============================================================
    //  Test 25: Multiple Beneficiaries
    // ============================================================

    #[test(aptos = @aptos_framework, admin = @0xCAFE, alice = @0xA11CE, bob = @0xB0B)]
    public fun test_multiple_beneficiaries(
        aptos:  &signer,
        admin:  &signer,
        alice:  &signer,
        bob:    &signer,
    ) {
        let (burn, mint) = init_env(aptos);
        new_account(&mint, admin, 5_000_000_000u64);
        new_account(&mint, alice, 0);
        new_account(&mint, bob,   0);
        vault::init_vault(admin);

        let vault_address = signer::address_of(admin);
        vault::deposit_tokens(admin, vault_address, 3_000_000_000u64);

        // Allocate to both
        vault::allocate_tokens(admin, vault_address, signer::address_of(alice), 1_000_000_000u64);
        vault::allocate_tokens(admin, vault_address, signer::address_of(bob),   500_000_000u64);

        let (_, _, available, allocated) = vault::get_vault_info(vault_address);
        assert!(available == 1_500_000_000u64, 0);
        assert!(allocated == 1_500_000_000u64, 1);

        // Both claim
        vault::claim_tokens(alice, vault_address);
        vault::claim_tokens(bob,   vault_address);

        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) == 1_000_000_000u64, 2);
        assert!(coin::balance<AptosCoin>(signer::address_of(bob))   == 500_000_000u64,   3);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

}
