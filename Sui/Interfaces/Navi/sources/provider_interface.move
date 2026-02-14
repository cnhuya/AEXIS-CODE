module 0x0::QiaraMultiAssetVaultV1 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use std::string::{Self, String};
    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};
    use sui::event;
    use 0x0::QiaraVariablesV1::{Self as vars}; 
    use 0x0:QiaraDelegatorV1::{Self as delegator, AdminCap, Vault};

// --- Errors ---
    const ENotSupported: u64 = 0;
    const EInsufficientPermission: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EAssetNotMatchedByRegistry: u64 = 3;
    const EDelegatorAlreadySet: u64 = 4;
    const EDelegatorNotSet: u64 = 5;
    const EInsufficientBalance: u64 = 6;
    const EVaultAlreadyExists: u64 = 7;

// --- Events ---
    public struct TokenListed has copy, drop {
        vault_id: ID,
        token_type: String,
        provider: String
    }

    public struct Deposit has copy, drop {
        vault_id: ID,
        user: address,
        token_type: String,
        amount: u64,
        provider: String
    }

    public struct WithdrawGrant has copy, drop {
        vault_id: ID,
        user: address,
        token_type: String,
        amount: u64,
        provider: String
    }

    public struct Withdrawal has copy, drop {
        vault_id: ID,
        user: address,
        token_type: String,
        amount: u64,
        provider: String
    }

// Structs

    public struct ReserveKey<phantom T> has copy, drop, store {}

    public struct AllowanceKey has copy, drop, store {
        user: address,
        token_type: TypeName
    }

    public struct SupportedTokenKey has copy, drop, store {
        token_type: TypeName
    }

// --- Initialization ---

    fun init(ctx: &mut TxContext) {
    }

// --- Permissionless Asset Listing ---

    // --- Administrative Functions ---
    /// Only the Delegator (holding AdminCap) can grant specific withdrawal rights
    public entry fun grant_withdrawal_permission<T>(vault: &mut Vault, admin: &AdminCap, nullifiers: &mut Nullifiers, public_inputs: vector<u8>,proof_points: vector<u8>) {
        let (user, amount) = delegator::verifyZK<T>(vault, admin, nullifiers, user, amount)
        
        assert!(admin.vault_id == object::id(vault), ENotAuthorized);
        internal_grant<T>(vault, user, amount);

        event::emit(WithdrawGrant {
            vault_id: object::id(vault),
            user: user,
            token_type: string::from_ascii(type_name::get_module(&type_name::get<T>())),
            amount,
            provider: vault.provider_name, // Assuming this is a String in your Vault struct
        });

    }

    // --- User Functions ---
    public entry fun deposit<T>(vault: &mut Vault, mut coin: Coin<T>, amount: u64, ctx: &mut TxContext) {
        let token_type = type_name::get<T>();
        assert!(df::exists_(&vault.id, SupportedTokenKey { token_type }), ENotSupported);
        
        // Ensure the coin has enough balance
        assert!(coin::value(&coin) >= amount, EInsufficientBalance);

        let sender = tx_context::sender(ctx);

        // 1. Handle the amount splitting
        // If the coin is exactly the amount, we take it all. 
        // Otherwise, we split it and send the change back.
        let deposit_coin = if (coin::value(&coin) == amount) {
            coin
        } else {
            let leftover = coin::split(&mut coin, amount, ctx);
            transfer::public_transfer(coin, sender); // Send change back to user
            leftover
        };

        // 2. Setup or get the reserve
        let reserve_key = ReserveKey<T> {};
        if (!df::exists_(&vault.id, reserve_key)) {
            df::add(&mut vault.id, reserve_key, balance::zero<T>());
        };
        
        let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
        
        // 3. Join the split amount to the reserve
        balance::join(reserve, coin::into_balance(deposit_coin));

        // 4. Update internal accounting with the specific amount
        //update_allowance<T>(vault, sender, amount);

        event::emit(Deposit {
            vault_id: object::id(vault),
            user: sender,
            token_type: string::from_ascii(type_name::get_module(&type_name::get<T>())),
            amount,
            provider: vault.provider_name, // Assuming this is a String in your Vault struct
        });

    }
    public entry fun withdraw<T>(vault: &mut Vault, amount: u64, receiver: address, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let token_type = type_name::get<T>();
        let allowance_key = AllowanceKey { user: sender, token_type };

        assert!(df::exists_(&vault.id, allowance_key), EInsufficientPermission);
        let allowance = df::borrow_mut<AllowanceKey, u64>(&mut vault.id, allowance_key);
        assert!(*allowance >= amount, EInsufficientPermission);
        
        *allowance = *allowance - amount;

        let reserve_key = ReserveKey<T> {};
        let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
        let withdrawn_balance = balance::split(reserve, amount);

        transfer::public_transfer(coin::from_balance(withdrawn_balance, ctx), receiver);

        event::emit(Withdrawal {
            vault_id: object::id(vault),
            user: sender,
            token_type: string::from_ascii(type_name::get_module(&type_name::get<T>())),
            amount,
            provider: vault.provider_name, // Assuming this is a String in your Vault struct
        });

    }

// --- Internal Helpers ---
    fun internal_grant<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        assert!(df::exists_(&vault.id, SupportedTokenKey { token_type }), ENotSupported);
        update_allowance<T>(vault, user, amount);
    }

    fun update_allowance<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        let key = AllowanceKey { user, token_type };
        if (df::exists_(&vault.id, key)) {
            let current = df::borrow_mut<AllowanceKey, u64>(&mut vault.id, key);
            *current = *current + amount;
        } else {
            df::add(&mut vault.id, key, amount);
        };
    }
}