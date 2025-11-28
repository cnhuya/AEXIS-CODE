module dev::QiaraStakingV3{
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
    use dev::QiaraTokensMetadataV4::{Self as TokensMetadata};
    use dev::QiaraStakingThirdPartyV1::{Self as StakingThirdParty};

    // For simplicity constant undecentralized unlock period due to re-dependancy loop cycle that would occur,
    // due to the fact that governance is using this module for voting power.
    // -------------------------------------------------------------------
    // However in the future, when there is official price oracle for Qiara token, it could be made via using lock function in margin and using
    // that as voting power, could be interesting & unique concept, however needs to be throughfully researched and studied.
    const SECONDS_IN_WEEK: u64 = 604_800;

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 2;
    const ERROR_USER_NOT_INITIALIZED: u64 = 3;

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

// === EVENTS === //
    #[event]
    struct StakeEvent has copy, drop, store {
        address: address,
        coin: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct RequestUnstakeEvent has copy, drop, store {
        address: address,
        coin: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct UnstakeEvent has copy, drop, store {
        address: address,
        coin: String,
        amount: u64,
        time: u64
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

            event::emit(StakeEvent {
                address: signer::address_of(signer),
                coin: type_info::type_name<QiaraToken>(),
                amount: amount,
                time: timestamp::now_seconds() 
            });

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

            event::emit(RequestUnstakeEvent {
                address: signer::address_of(signer),
                coin: type_info::type_name<QiaraToken>(),
                amount: amount,
                time: timestamp::now_seconds() 
            });

        }
        public fun qiara_withdraw(signer: &signer, cap: Permission) acquires QiaraVault, UserTracker {
            assert!(exists<QiaraVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<QiaraVault>(@dev);

            let total = calculate_total_unlocks<QiaraToken>(*find_user_requests<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer));
            Qiara::entry_withdraw_from_store(signer, vault.balance, total);
       
            event::emit(UnstakeEvent {
                address: signer::address_of(signer),
                coin: type_info::type_name<QiaraToken>(),
                amount: total,
                time: timestamp::now_seconds() 
            });
        }

    // Interface for Basic Coin Token Types
        public fun stake<Token>(signer: &signer, amount: u64) acquires CoinVault, UserTracker {
            assert!(exists<CoinVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<CoinVault<Token>>(@dev);

            let coins = coin::withdraw(signer, amount);
            coin::merge(&mut vault.balance, coins);

            let user_stake = find_user<Token>(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer));
            *user_stake = *user_stake + amount;
      
            event::emit(StakeEvent {
                address: signer::address_of(signer),
                coin: type_info::type_name<Token>(),
                amount: amount,
                time: timestamp::now_seconds() 
            });
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
       
            event::emit(RequestUnstakeEvent {
                address: signer::address_of(signer),
                coin: type_info::type_name<Token>(),
                amount: amount,
                time: timestamp::now_seconds() 
            });
        }
        public fun withdraw<Token>(signer: &signer) acquires CoinVault, UserTracker {
            assert!(exists<CoinVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
            let vault = borrow_global_mut<CoinVault<Token>>(@dev);

            let total = calculate_total_unlocks<QiaraToken>(*find_user_requests<QiaraToken>(borrow_global_mut<UserTracker>(@dev), signer));

            let coins = coin::extract<Token>(&mut vault.balance, total);
            coin::deposit(signer::address_of(signer), coins);
    
            event::emit(UnstakeEvent {
                address: signer::address_of(signer),
                coin: type_info::type_name<Token>(),
                amount: total,
                time: timestamp::now_seconds() 
            });
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
        let unlock_period = StakingThirdParty::return_unlock_period();
        let len = vector::length(&vect);
        let i = 0;
        while (i < len) {
            let req = vector::borrow(&vect, i);
            if (timestamp::now_seconds() >= req.request_time + unlock_period ) {
                total = total + req.amount;
            };
            i = i + 1;
        };
        return total
    }

    fun calculate_total_vote_power(map: Map<String, u64>): u256{
        let keys = map::keys(&map);
    
        let base_weight = (StakingThirdParty::return_base_weight() as u256);
        let usd_to_weight_scale = (StakingThirdParty::return_coins_usd_scale() as u256);

        let len_keys = vector::length(&keys);
        let total_vote_power: u256 = 0;
        while(len_keys > 0){
            let key = vector::borrow(&keys, len_keys-1);
            let value = (*map::borrow(&map, key) as u256);
            if(*key != type_info::type_name<QiaraToken>()){
                let metadata = TokensMetadata::get_coin_metadata_by_res(*key);
                total_vote_power = total_vote_power * ((value * TokensMetadata::get_coin_metadata_price(&metadata))/usd_to_weight_scale);
            } else if (*key == type_info::type_name<QiaraToken>()){
                total_vote_power = total_vote_power + value;
            };
            len_keys = len_keys-1;
        };
        return base_weight+ total_vote_power
    }
// === VIEW FUNCTIONS === //
    #[view]
        public fun get_voting_power(address: address): u256 acquires UserTracker{
            let tracker = borrow_global<UserTracker>(@dev);

            if(!table::contains(&tracker.tracker, address)) {
                abort ERROR_USER_NOT_INITIALIZED
            };

            let user_map = table::borrow(&tracker.tracker, address);
            return calculate_total_vote_power(*user_map)
        }
}
