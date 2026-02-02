module dev::QiaraStakingV1{
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


    use dev::QiaraTokensMetadataV1::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV1::{Self as TokensCore};
    use dev::QiaraTokensStoragesV1::{Self as TokensStorages};
    use dev::QiaraStakingThirdPartyV1::{Self as StakingThirdParty};

    use dev::QiaraChainTypesV2::{Self as ChainTypes};
    use dev::QiaraTokenTypesV2::{Self as TokensType};


    use dev::QiaraValidatorsV1::{Self as Validators, Access as ValidatorsAccess};
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

    struct Permissions has key, store, drop {
        validators: ValidatorsAccess,
    }

// === STRUCTS === //
    // i.e Address -> Token -> Chain -> Amount
    struct UserTracker has key, store {
        tracker: Table<address, Map<String,Map<String, u64>>>,
        unstake_requests: Table<address, Map<String, Map<String, vector<UnstakeRequest>>>>,
    }

    struct UnstakeRequest has copy, drop, store {
        amount: u64,
        request_time: u64,
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
            move_to(admin, UserTracker { tracker: table::new<address, Map<String, Map<String, u64>>>(), unstake_requests: table::new<address, Map<String, Map<String, vector<UnstakeRequest>>>>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { validators: Validators::give_access(admin) });
        };
    }
// === FUNCTIONS === //
    // Management functions
        public entry fun register_validator(signer: &signer, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>) acquires Permissions, UserTracker {
            Validators::register_validator(signer, pub_key_x, pub_key_y, pub_key, get_voting_power(signer::address_of(signer)), Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
        public entry fun change_validator_poseidon_pubkeys(signer: &signer, pub_key_x: String, pub_key_y: String) acquires Permissions {
            Validators::change_validator_poseidon_pubkeys(signer, pub_key_x, pub_key_y, Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
        public entry fun change_validator_pubkey(signer: &signer, pub_key: vector<u8>) acquires Permissions {
            Validators::change_validator_pubkey(signer, pub_key, Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
        public entry fun change_staker_validator(signer: &signer, new_validator: address) acquires  Permissions {
            Validators::change_staker_validator(signer, new_validator, Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
    // Native Interface
        public fun stake(signer: &signer, parent: address, token: String, chain: String, amount: u64, perm: Permission) acquires UserTracker {
            let revenue_storage = TokensStorages::return_fee_storage(token, chain);
            let staking_fee_amount = simulate_staking_fee((amount as u256));
            let wallet = primary_fungible_store::primary_store(signer::address_of(signer), TokensCore::get_metadata(token));

            let fee_fa = TokensCore::withdraw(wallet, (staking_fee_amount as u64), chain);

            find_user(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer), token, chain, amount);

            TokensCore::deposit(revenue_storage, fee_fa, chain);

            event::emit(StakeEvent {
                address: signer::address_of(signer),
                token: token,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });

        }
        public fun unstake(signer: &signer, token: String, chain: String, amount: u64, perm: Permission) acquires UserTracker {
            find_user(borrow_global_mut<UserTracker>(@dev), signer::address_of(signer), token, chain, amount);

            let requests = find_user_requests(borrow_global_mut<UserTracker>(@dev), signer, token, chain);
            vector::push_back(requests, UnstakeRequest {amount: amount,request_time: timestamp::now_seconds()});

            event::emit(RequestUnstakeEvent {
                address: signer::address_of(signer),
                token: token,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });

        }
        public fun withdraw(signer: &signer, token: String, chain: String, perm: Permission) acquires UserTracker {
            let total = calculate_total_unlocks(*find_user_requests(borrow_global_mut<UserTracker>(@dev), signer, token, chain));

            event::emit(UnstakeEvent {
                address: signer::address_of(signer),
                token: token,
                chain: chain,
                amount: total,
                time: timestamp::now_seconds() 
            });
        }


// === HELPER FUNCTIONS === //
    fun find_user(tracker: &mut UserTracker, address: address, token: String, chain: String, value: u64) {
        
/*    struct UserTracker has key, store {
        tracker: Table<address, Map<String,Map<String, u64>>>,
        unstake_requests: Table<address, Map<String, Map<String, vector<UnstakeRequest>>>>,
    }
*/
        // Check if address exists in the tracker
        if (!table::contains(&tracker.tracker, address)) {
            // Create a new Table for this address
            let user_table = map::new<String, Map<String, u64>>();
            table::add(&mut tracker.tracker, address, user_table);
        };
        
        // Get the user's token table
        let user_table = table::borrow_mut(&mut tracker.tracker, address);
        
        // Check if token exists in the user's table
        if (!map::contains_key(user_table, &token)) {
            // Create a new SimpleMap for this token
            let chain_map = map::new<String, u64>();
            map::add(user_table, token, chain_map);
        };
        
        // Get the token's chain map
        let chain_map = map::borrow_mut(user_table, &token);
        
        // Check if chain exists in the chain map
        if (!map::contains_key(chain_map, &chain)) {
            map::add(chain_map, chain, 0);
        };
        
        // Return mutable reference to the u64 value
        let previous = map::borrow(chain_map, &chain);
        map::upsert(chain_map, copy chain, *previous+value);
    }

    fun find_user_requests(tracker: &mut UserTracker, user: &signer,  token: String, chain: String): &mut vector<UnstakeRequest> {

        if(!table::contains(&tracker.unstake_requests, signer::address_of(user))) {
            table::add(&mut tracker.unstake_requests, signer::address_of(user), map::new<String, Map<String, vector<UnstakeRequest>>>());
        };

        let user = table::borrow_mut(&mut tracker.unstake_requests, signer::address_of(user));

        if(!map::contains_key(user, &token)) {
            map::add(user, token, map::new<String, vector<UnstakeRequest>>());
        };
        let user1 = map::borrow_mut(user, &token);

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

    fun calculate_total_vote_power(map: &Map<String, Map<String, u64>>): u256 {
        let total_vote_power: u256 = 0;
        let tokens = TokensType::return_full_nick_names_list();
        let token_count = vector::length(&tokens);
        let i = 0;
        
        // Loop through all tokens
        while (i < token_count) {
            let token = vector::borrow(&tokens, i);
            
            // Check if this token exists in the table
            if (map::contains_key(map, token)) {
                let map = map::borrow(map, token);
                let chains = map::keys(map);
                let chain_count = vector::length(&chains);
                let j = 0;
                
                let metadata = TokensMetadata::get_coin_metadata_by_symbol(*token);
                let metadata_denom = TokensMetadata::get_coin_metadata_denom(&metadata);
                
                // Avoid division by zero
                assert!(metadata_denom > 0, 25565);
                
                // Loop through all chains for this token
                while (j < chain_count) {
                    let chain = vector::borrow(&chains, j);
                    let value = (*map::borrow(map, chain) as u256);
                    
                    if (*token != utf8(b"Qiara")) {
                        // Calculate USD value
                        let price = TokensMetadata::get_coin_metadata_price(&metadata);
                        let usd_value = value * (price as u256);
                        
                        // Calculate power with safe division
                        if (usd_value > 0 && metadata_denom > 0) {
                            let x = usd_value / (metadata_denom as u256);
                            let tier_efficiency = (TokensMetadata::get_coin_metadata_tier_efficiency(&metadata) as u256);
                            let additional_power = staking_vote_weight(tier_efficiency, x);
                            total_vote_power = total_vote_power + (additional_power / 10000);
                        };
                    } else {
                        // Qiara token - add raw value
                        total_vote_power = total_vote_power + value;
                    };
                    
                    j = j + 1;
                };
            };
            
            i = i + 1;
        };
        
        return total_vote_power
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
    public fun return_address_staked(address: address, token: String): Map<String, u64> acquires UserTracker {

        let tracker = borrow_global<UserTracker>(@dev);

        if(!table::contains(&tracker.tracker, address)) {
             abort ERROR_USER_NOT_INITIALIZED
        };
        let user = table::borrow(&tracker.tracker, address);

        if(!map::contains_key(user, &token)) {
             abort ERROR_USER_DOESNT_STAKED_THIS_TOKEN_YET
        };

        *map::borrow(user, &token)
    }
}
