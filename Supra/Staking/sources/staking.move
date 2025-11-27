module dev::QiaraStakingV2{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::event;
    use supra_framework::coin::{Self, Coin};
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use supra_framework::object::{Self as object, Object};
    use std::table::{Self, Table};

    use dev::QiaraTestV34::{Self as Qiara, Qiara as QiaraToken};
    use dev::QiaraStorageV32::{Self as storage};

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

    // reserve for inflation. 
    struct QiaraVault has key, store {
        balance: Object<FungibleStore>,
    }

    struct CoinVault<phantom Token> has key {
        balance: coin::Coin<Token>,
    }

    struct UnstakeRequest has copy, drop, store {
        amount: u64,
        request_time: u64,
    }

    // i.e Address -> Token Resource -> Amount
    struct UserTracker has key, store {
        tracker: Table<address, Map<String, u64>>,
        unstake_requests: Table<address, Map<String, vector<UnstakeRequest>>>,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<UserTracker>(@dev)) {
            move_to(admin, UserTracker { tracker: table::new<address, Map<String, u64>>(), unstake_requests: table::new<address, Map<String, vector<UnstakeRequest>>>() });
        };
        if (!exists<QiaraVault>(@dev)) {
            let balance = fungible_asset::create_store(&object::create_object(signer::address_of(admin)), Qiara::get_metadata());
            move_to(admin, QiaraVault { balance });
        };
    }
// === FUNCTIONS === //
    public fun init_vault<Token>(admin: &signer, cap: Permission) {
        if (!exists<CoinVault<Token>>(@dev)) {
            move_to(admin, CoinVault { balance: coin::zero<Token>() });
        }
    }

    // Interface for Qiara Fungible Asset
        public fun qiara_stake(signer: &signer, amount: u64, cap: Permission) acquires QiaraVault, UserTracker {
            assert!(exists<QiaraVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<QiaraVault>(@dev);

            let coins = Qiara::withdraw_from_user_store(signer, amount);
            Qiara::deposit_to_store(signer, vault.balance, coins);

            let user_stake = find_user<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer));
            *user_stake = *user_stake + amount;
        }
        public fun qiara_unstake(signer: &signer, amount: u64, cap: Permission) acquires QiaraVault, UserTracker {
            assert!(exists<QiaraVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<QiaraVault>(@dev);

            let user_stake = find_user<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer));
            *user_stake = *user_stake - amount;

            let requests = find_user_requests<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer);
            let request = UnstakeRequest {
                amount: amount,
                request_time: timestamp::now_seconds(),
            };
            vector::push_back(requests, request);

        }
        public fun qiara_withdraw(signer: &signer, cap: Permission) acquires QiaraVault, UserTracker {
            assert!(exists<QiaraVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<QiaraVault>(@dev);

            let total = calculate_total_unlocks<QiaraToken>(*find_user_requests<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer));
            Qiara::entry_withdraw_from_store(signer, vault.balance, total);
        }

    // Interface for Basic Coin Token Types
        public fun stake<Token>(signer: &signer, amount: u64) acquires CoinVault, UserTracker {
            assert!(exists<CoinVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<CoinVault<Token>>(@dev);

            let coins = coin::withdraw(signer, amount);
            coin::merge(&mut vault.balance, coins);

            let user_stake = find_user<Token>(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer));
            *user_stake = *user_stake + amount;
        }
        public fun unstake<Token>(signer: &signer, amount: u64) acquires CoinVault, UserTracker {
            assert!(exists<CoinVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<CoinVault<Token>>(@dev);

            let user_stake = find_user<Token>(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer));
            *user_stake = *user_stake - amount;

            let requests = find_user_requests<Token>(borrow_global_mut<UserTracker>(@dev), signer);
            let request = UnstakeRequest {
                amount: amount,
                request_time: timestamp::now_seconds(),
            };
            vector::push_back(requests, request);
        }
        public fun withdraw<Token>(signer: &signer) acquires CoinVault, UserTracker {
            assert!(exists<CoinVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<CoinVault<Token>>(@dev);

            let total = calculate_total_unlocks<QiaraToken>(*find_user_requests<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer));

            let coins = coin::extract<Token>(&mut vault.balance, total);
            coin::deposit(signer::address_of(signer), coins);
        }
// === HELPER FUNCTIONS === //
    fun find_user<Token>(tracker: &mut UserTracker, address: address): &mut u64 {

        if(!table::contains(&tracker.tracker, address)) {
            table::add(&mut tracker.tracker, address, map::new<String, u64>());
        };

        let user = table::borrow_mut(&mut tracker.tracker, address);

        if(!map::contains_key(user, &type_info::type_name<Token>())) {
            map::upsert(user, type_info::type_name<Token>(), 0);
        };

        return map::borrow_mut(user, &type_info::type_name<Token>())
    }

    fun find_user_requests<Token>(tracker: &mut UserTracker, user: &signer): &mut vector<UnstakeRequest> {

        if(!table::contains(&tracker.unstake_requests, signer::address_of(user))) {
            table::add(&mut tracker.unstake_requests, signer::address_of(user), map::new<String, vector<UnstakeRequest>>());
        };

        let user = table::borrow_mut(&mut tracker.unstake_requests, signer::address_of(user));

        if(!map::contains_key(user, &type_info::type_name<Token>())) {
            map::upsert(user, type_info::type_name<Token>(), vector::empty<UnstakeRequest>());
        };

        return map::borrow_mut(user, &type_info::type_name<Token>())
    }

    fun calculate_total_unlocks<Token>(vect: vector<UnstakeRequest>): u64 {
        let total: u64 = 0;
        let len = vector::length(&vect);
        let i = 0;
        while (i < len) {
            let req = vector::borrow(&vect, i);
            if (timestamp::now_seconds() >= req.request_time + storage::expect_u64(storage::viewConstant(utf8(b"QiaraStaking"), utf8(b"UNLOCK_PERIOD")))) {
                total = total + req.amount;
            };
            i = i + 1;
        };
        return total
    }
}
