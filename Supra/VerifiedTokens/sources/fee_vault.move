module dev::QiaraFeeVaultV5{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::event;
    use supra_framework::coin::{Self, Coin};


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
   
    struct Vault<phantom T> has key {
        balance: coin::Coin<T>,
    }


// === EVENTS === //
    #[event]
    struct PayFeeEvent has copy, drop, store {
        amount: u64,
        payer: address,
        token: String,
        time: u64,
        type: String,
    }

    #[event]
    struct CollectFeeEvent has copy, drop, store {
        amount: u64,
        collector: address,
        token: String,
        time: u64
    }

// === FUNCTIONS === //
    fun init_module(admin: &signer) {
    }


    public fun pay_fee<Token>(user: &signer, coins: Coin<Token>, type: String) acquires Vault {
        assert!(exists<Vault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<Vault<Token>>(@dev);

        let amount = coin::value(&coins);
        coin::merge(&mut vault.balance, coins);

        event::emit(PayFeeEvent {
            amount: amount,
            payer: signer::address_of(user),
            token: type_info::type_name<Token>(),
            time: timestamp::now_seconds(),
            type: type,
        });
    }

    public fun collect_fee<Token>(user: &signer, amount: u64) acquires Vault {
        assert!(exists<Vault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<Vault<Token>>(@dev);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        event::emit(CollectFeeEvent {
            amount: amount,
            collector: signer::address_of(user),
            token: type_info::type_name<Token>(),
            time: timestamp::now_seconds(),
        });
    }

    #[view]
    public fun get_balance_amount<Token>(): u64 acquires Vault {
        assert!(exists<Vault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<Vault<Token>>(@dev);
        coin::value(&vault.balance)
    }

    public fun init_fee_vault<Token>(admin: &signer) {
        if (!exists<Vault<Token>>(@dev)) {
            move_to(admin, Vault {balance: coin::zero<Token>()});
        }
    }
}
