module dev::QiaraTokensFeeVaultV5{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, FungibleAsset};
    use supra_framework::object::{Self, Object};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 2;


// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }


// === STRUCTS === //
   
    struct Vault<Chain> has key {
        balance: Object<FungibleStore<Chain>>, // private
    }


// === EVENTS === //
    #[event]
    struct PayFeeEvent has copy, drop, store {
        amount: u64,
        payer: vector<u8>,
        token: String,
        chain: String,
        time: u64,
        type: String,
    }

    #[event]
    struct CollectFeeEvent has copy, drop, store {
        amount: u64,
        collector: address,
        token: String,
        chain: String,
        time: u64
    }

// === FUNCTIONS === //
    fun init_module(admin: &signer) {
    }


    public fun pay_fee<Chain>(user: vector<u8>, fa: FungibleAsset, type: String, cap: Permission) acquires Vault {
        assert!(exists<Vault<Chain>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<Vault<Chain>>(@dev);

        let amount = coin::value(&coins);
        coin::merge(&mut vault.balance, coins);

        event::emit(PayFeeEvent {
            amount: amount,
            payer: user,
            token: fungible_asset::name(fungible_asset::metadata_from_asset(&fa)),
            chain: type_info::type_name<Chain>(),
            time: timestamp::now_seconds(),
            type: type,
        });
    }

    public fun collect_fee<Chain>(user: &signer, amount: u64) acquires Vault {
        assert!(exists<Vault<Chain>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<Vault<Chain>>(@dev);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        event::emit(CollectFeeEvent {
            amount: amount,
            collector: signer::address_of(user),
            token: fungible_asset::name(fungible_asset::metadata_from_asset(&fa)),
            chain: type_info::type_name<Chain>(),
            time: timestamp::now_seconds(),
        });
    }

    #[view]
    public fun get_balance_amount<Chain>(): u64 acquires Vault {
        assert!(exists<Vault<Chain>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<Vault<Chain>>(@dev);
        fungible_asset::amount(&vault.balance)
    }

    public fun init_fee_vault<Chain>(admin: &signer) {
        if (!exists<Vault<Chain>>(@dev)) {
            move_to(admin, Vault {balance: fungible_asset::zero<Chain>()});
        }
    }
}
