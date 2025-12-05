module dev::QiaraStakingV6{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use supra_framework::object::{Self as object, Object};
    use std::table::{Self, Table};

    use dev::QiaraTokensMetadataV33::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV33::{Self as TokensCore};
    use dev::QiaraTokensStoragesV33::{Self as TokensStorages};
    use dev::QiaraStakingThirdPartyV2::{Self as StakingThirdParty};

    use dev::QiaraChainTypesV19::{Self as ChainTypes};
    use dev::QiaraTokenTypesV19::{Self as TokensType};

    // For simplicity constant undecentralized unlock period due to re-dependancy loop cycle that would occur,
    // due to the fact that governance is using this module for voting power.
    // -------------------------------------------------------------------
    // However in the future, when there is official price oracle for Qiara token, it could be made via using lock function in margin and using
    // that as voting power, could be interesting & unique concept, however needs to be throughfully researched and studied.

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_USER_NOT_INITIALIZED: u64 = 2;
    const ERROR_NOTHING_TO_UNSTAKE: u64 = 3;
    const ERROR_USER_DOESNT_STAKED_THIS_TOKEN_YET: u64 = 4;
    const ERROR_UNSUPPORTED_OR_NOT_YET_INNITIALIZED_TOKEN: u64 = 5;

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

    // Stores all staking stores for different tokens on a specific chain
    struct StakingStorage has key {
        balances: Table<String, Map<String, Object<FungibleStore>>>
    }


    struct UnstakeRequest has copy, drop, store {
        amount: u64,
        request_time: u64,
    }

    // i.e Address -> Token -> Chain -> Amount
    struct UserTracker has key, store {
        tracker: Table<address, Table<String,Map<String, u64>>>,
        unstake_requests: Table<address, Table<String, Map<String, vector<UnstakeRequest>>>>,
    }

// === EVENTS === //
    #[event]
    struct StakeEvent has copy, drop, store {
        address: address,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct RequestUnstakeEvent has copy, drop, store {
        address: address,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct UnstakeEvent has copy, drop, store {
        address: address,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<UserTracker>(@dev)) {
            move_to(admin, UserTracker { tracker: table::new<address, Table<String, Map<String, u64>>>(), unstake_requests: table::new<address, Table<String, Map<String, vector<UnstakeRequest>>>>() });
        };
        if (!exists<StakingStorage>(@dev)) {
            move_to(admin, StakingStorage { balances: table::new<String, Map<String, Object<FungibleStore>>>() });
        };
    }
// === FUNCTIONS === //

    public fun ensure_storages_exists(staking_storage: &mut StakingStorage, token: String, chain: String): Object<FungibleStore>{
        ChainTypes::ensure_valid_chain_name(&chain);
        
        let metadata = TokensCore::get_metadata(token);

        // Stake
        if (!table::contains(&staking_storage.balances, token)) {
            table::add(&mut staking_storage.balances, token, map::new<String, Object<FungibleStore>>());
        };
        let stake = table::borrow_mut(&mut staking_storage.balances, token);
        if (!map::contains_key(stake, &chain)) {
            map::add( stake, chain, primary_fungible_store::ensure_primary_store_exists<Metadata>(@dev, metadata));
        };
        return *map::borrow(stake, &chain)
    }

    fun tttta(id: u64){
        abort(id);
    }

    // Interface for Qiara Fungible Asset
        public entry fun stake(signer: &signer, token: String, chain: String, amount: u64) acquires StakingStorage, UserTracker {
            let stake_storage = ensure_storages_exists(borrow_global_mut<StakingStorage>(@dev), token, chain);
            let revenue_storage = TokensStorages::return_fee_storage(token, chain);
            let staking_fee_amount = simulate_staking_fee((amount as u256));
            let wallet = primary_fungible_store::primary_store(signer::address_of(signer), TokensCore::get_metadata(token));

            let fa = TokensCore::withdraw(wallet, amount, chain);
            let fee_fa = fungible_asset::extract(&mut fa, (staking_fee_amount as u64));

            let user_stake = find_user(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer), token, chain);
            *user_stake = *user_stake + amount;
            TokensCore::deposit(stake_storage, fa, chain);
            TokensCore::deposit(revenue_storage, fee_fa, chain);

            event::emit(StakeEvent {
                address: signer::address_of(signer),
                token: token,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });

        }
        public entry fun unstake(signer: &signer, token: String, chain: String, amount: u64) acquires StakingStorage, UserTracker {
            ensure_storages_exists(borrow_global_mut<StakingStorage>(@dev), token, chain);

            let user_stake = find_user(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer), token, chain);
            *user_stake = *user_stake - amount;

            let requests = find_user_requests(borrow_global_mut<UserTracker>(@dev), signer, token, chain);
            let request = UnstakeRequest {
                amount: amount,
                request_time: timestamp::now_seconds(),
            };
            vector::push_back(requests, request);

            event::emit(RequestUnstakeEvent {
                address: signer::address_of(signer),
                token: token,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });

        }
        public entry fun withdraw(signer: &signer, token: String, chain: String,) acquires StakingStorage, UserTracker {
            let stake_storage = ensure_storages_exists(borrow_global_mut<StakingStorage>(@dev), token, chain);

            let wallet = primary_fungible_store::primary_store(signer::address_of(signer), TokensCore::get_metadata(token));
            let total = calculate_total_unlocks(*find_user_requests(borrow_global_mut<UserTracker>(@dev), signer, token, chain));
            let fa = TokensCore::withdraw(wallet, total, chain);
            TokensCore::deposit(stake_storage, fa, chain);

            event::emit(UnstakeEvent {
                address: signer::address_of(signer),
                token: token,
                chain: chain,
                amount: total,
                time: timestamp::now_seconds() 
            });
        }


// === HELPER FUNCTIONS === //
    fun find_user(tracker: &mut UserTracker, address: address, token: String, chain: String): &mut u64 {
        
        // Check if address exists in the tracker
        if (!table::contains(&tracker.tracker, address)) {
            // Create a new Table for this address
            let user_table = table::new<String, Map<String, u64>>();
            table::add(&mut tracker.tracker, address, user_table);
        };
        
        // Get the user's token table
        let user_table = table::borrow_mut(&mut tracker.tracker, address);
        
        // Check if token exists in the user's table
        if (!table::contains(user_table, token)) {
            // Create a new SimpleMap for this token
            let chain_map = map::new<String, u64>();
            table::add(user_table, token, chain_map);
        };
        
        // Get the token's chain map
        let chain_map = table::borrow_mut(user_table, token);
        
        // Check if chain exists in the chain map
        if (!map::contains_key(chain_map, &chain)) {
            map::add(chain_map, chain, 0);
        };
        
        // Return mutable reference to the u64 value
        map::borrow_mut(chain_map, &chain)
    }

    fun find_user_requests(tracker: &mut UserTracker, user: &signer,  token: String, chain: String): &mut vector<UnstakeRequest> {

        if(!table::contains(&tracker.unstake_requests, signer::address_of(user))) {
            table::add(&mut tracker.unstake_requests, signer::address_of(user), table::new<String, Map<String, vector<UnstakeRequest>>>());
        };

        let user = table::borrow_mut(&mut tracker.unstake_requests, signer::address_of(user));

        if(!table::contains(user, token)) {
            table::add(user, token, map::new<String, vector<UnstakeRequest>>());
        };
        let user1 = table::borrow_mut(user, token);

        if(!map::contains_key(user1, &chain)) {
            map::add(user1, chain, vector::empty<UnstakeRequest>());
        };

        return map::borrow_mut(user1, &chain)
    }

    fun calculate_total_unlocks(vect: vector<UnstakeRequest>): u64 {
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
        assert!(total > 0, ERROR_NOTHING_TO_UNSTAKE);
        return total
    }

    #[view]
    public fun staking_vote_weight(efficiency: u256, usd_value: u256): u256{
        let tier_slashing = (StakingThirdParty::return_efficiency_slashing() as u256);
        return (usd_value/tier_slashing)*efficiency
    }

    #[view]
    public fun simulate_staking_fee(amount: u256): u256{
        let staking_fee = (StakingThirdParty::return_staking_fee() as u256);
        return (staking_fee*amount)/1_000_000/100 
    }

    fun calculate_total_vote_power(table: &Table<String,Map<String, u64>>): u256{

        let total_vote_power: u256 = 0;
        let tokens = TokensType::return_all_tokens();
        let len_tokens = vector::length(&tokens);

        let base_weight = (StakingThirdParty::return_base_weight() as u256);

        while(len_tokens>0){ // checking for each token
            let token = vector::borrow(&tokens, len_tokens-1);
            let map = table::borrow(table, *token);
            let chains = map::keys(map); // chains
        

            let len_chains = vector::length(&chains);


            let metadata = TokensMetadata::get_coin_metadata_by_symbol(*token);
            while(len_chains > 0){ // checking for each chain
                let key = vector::borrow(&chains, len_chains-1);
                let value = (*map::borrow(map, key) as u256);
                if(*token != utf8(b"Qiara")){
                    let usd_value  = value * TokensMetadata::get_coin_metadata_price(&metadata);
                    let additional_power = staking_vote_weight((TokensMetadata::get_coin_metadata_tier_efficiency(&metadata) as u256), (usd_value/TokensMetadata::get_coin_metadata_denom(&metadata)));
                    total_vote_power = total_vote_power + ((additional_power as u256)/10000);
                } else if (*token == utf8(b"Qiara")){
                    total_vote_power = total_vote_power + value;
                };
                len_chains = len_chains-1;
            };
            len_tokens = len_tokens-1;
        };

        return base_weight+total_vote_power
    }
// === VIEW FUNCTIONS === //
    #[view]
        public fun get_voting_power(address: address): u256 acquires UserTracker{
            let tracker = borrow_global<UserTracker>(@dev);

            if(!table::contains(&tracker.tracker, address)) {
                abort ERROR_USER_NOT_INITIALIZED
            };

            let user_map = table::borrow(&tracker.tracker, address);
            return calculate_total_vote_power(user_map)
        }
    #[view]
    public fun return_staked(token: String): Map<String, Object<FungibleStore>> acquires StakingStorage {

        let staking_storage = borrow_global<StakingStorage>(@dev);

        if(!table::contains(&staking_storage.balances, token)) {
             abort ERROR_UNSUPPORTED_OR_NOT_YET_INNITIALIZED_TOKEN
        };

        *table::borrow(&staking_storage.balances, token)

    }
    #[view]
    public fun return_address_staked(address: address, token: String): Map<String, u64> acquires UserTracker {

        let tracker = borrow_global<UserTracker>(@dev);

        if(!table::contains(&tracker.tracker, address)) {
             abort ERROR_USER_NOT_INITIALIZED
        };
        let user = table::borrow(&tracker.tracker, address);

        if(!table::contains(user, token)) {
             abort ERROR_USER_DOESNT_STAKED_THIS_TOKEN_YET
        };

        *table::borrow(user, token)
    }
}
