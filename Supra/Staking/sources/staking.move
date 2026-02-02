module dev::QiaraStakingV2{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::bcs;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use supra_framework::object::{Self as object, Object};
    use std::table::{Self, Table};

    use dev::QiaraTokensSharedV3::{Self as TokensShared};
    use dev::QiaraTokensMetadataV3::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV3::{Self as TokensCore};
    use dev::QiaraTokensStoragesV3::{Self as TokensStorages};

    use dev::QiaraStakingThirdPartyV2::{Self as StakingThirdParty};

    use dev::QiaraChainTypesV4::{Self as ChainTypes};
    use dev::QiaraTokenTypesV4::{Self as TokensType};

    use dev::QiaraValidatorsV2::{Self as Validators, Access as ValidatorsAccess};

    use dev::QiaraEventV1::{Self as Event};
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
    // i.e Address -> Token -> Chain -> Provider -> Amount
    struct UserTracker has key, store {
        tracker: Table<String, Map<String, Map<String, Map<String, u64>>>>,
        unstake_requests: Table<String, Map<String, Map<String, Map<String, vector<UnstakeRequest>>>>>,
    }

    struct UnstakeRequest has copy, drop, store {
        amount: u64,
        request_time: u64,
    }


// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<UserTracker>(@dev)) {
            move_to(admin, UserTracker { tracker: table::new<String, Map<String, Map<String, Map<String, u64>>>>(), unstake_requests: table::new<String, Map<String, Map<String, Map<String, vector<UnstakeRequest>>>>>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { validators: Validators::give_access(admin) });
        };
    }
// === FUNCTIONS === //
    // Management functions
        public entry fun register_validator(signer: &signer, shared_storage_name: String, owner: vector<u8>, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>) acquires Permissions, UserTracker {
            TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
            Validators::register_validator(signer, shared_storage_name, owner, pub_key_x, pub_key_y, pub_key, get_voting_power(shared_storage_name), Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
        public entry fun change_validator_poseidon_pubkeys(signer: &signer, shared_storage_name: String, owner: vector<u8>,pub_key_x: String, pub_key_y: String) acquires Permissions {
            TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
            Validators::change_validator_poseidon_pubkeys(signer, shared_storage_name, owner, pub_key_x, pub_key_y, Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
        public entry fun change_validator_pubkey(signer: &signer, shared_storage_name: String, owner: vector<u8>, pub_key: vector<u8>) acquires Permissions {
            TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
            Validators::change_validator_pubkey(signer, shared_storage_name, owner, pub_key, Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
        public entry fun change_staker_validator(signer: &signer, shared_storage_name: String, owner: vector<u8>, new_validator: String) acquires  Permissions {
            TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
            Validators::change_staker_validator(signer, shared_storage_name, owner, new_validator, Validators::give_permission(&borrow_global_mut<Permissions>(@dev).validators));
        }
    // Native Interface
        public fun stake(signer: &signer, shared_storage_name: String, owner: vector<u8>, token: String, chain: String, provider: String, amount: u64, perm: Permission) acquires UserTracker {
            let revenue_storage = TokensStorages::return_fee_storage(token, chain);
            let staking_fee_amount = simulate_staking_fee((amount as u256));
            let wallet = primary_fungible_store::primary_store(signer::address_of(signer), TokensCore::get_metadata(token));

            let fee_fa = TokensCore::withdraw(wallet, (staking_fee_amount as u64), chain);

            find_user(borrow_global_mut<UserTracker>(@dev), owner, shared_storage_name,  bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount);

            TokensCore::deposit(revenue_storage, fee_fa, chain);

            let data = vector[
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Stake"))),
                Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
                Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&(amount as u256))),
            ];

            Event::emit_market_event(data);
        }
        public fun unstake(signer: &signer, shared_storage_name: String, owner: vector<u8>, token: String, chain: String, provider: String, amount: u64, perm: Permission) acquires UserTracker {
            find_user(borrow_global_mut<UserTracker>(@dev), owner, shared_storage_name,  bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount);

            let requests = find_user_requests(borrow_global_mut<UserTracker>(@dev), owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
            vector::push_back(requests, UnstakeRequest {amount: amount,request_time: timestamp::now_seconds()});

            let data = vector[
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Request Unstake"))),
                Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
                Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&(amount as u256))),
            ];

            Event::emit_market_event(data);

        }
        public fun withdraw(signer: &signer, shared_storage_name: String, owner: vector<u8>, token: String, chain: String, provider: String, perm: Permission) acquires UserTracker {
            let total = calculate_total_unlocks(*find_user_requests(borrow_global_mut<UserTracker>(@dev), owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider));

            let data = vector[
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Request Unstake"))),
                Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
                Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&token)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                Event::create_data_struct(utf8(b"amount"), utf8(b"u256"), bcs::to_bytes(&(total as u256))),
            ];

            Event::emit_market_event(data);

        }


// === HELPER FUNCTIONS === //
    fun find_user(tracker: &mut UserTracker, owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String, provider: String, value: u64) {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
       
        // Check if address exists in the tracker
        if (!table::contains(&tracker.tracker, shared_storage_name)) {
            // Create a new Table for this address
            let user_table = map::new<String, Map<String, Map<String, u64>>>();
            table::add(&mut tracker.tracker, shared_storage_name, user_table);
        };
        
        // Get the user's token table
        let user_table = table::borrow_mut(&mut tracker.tracker, shared_storage_name);
        
        // Check if token exists in the user's table
        if (!map::contains_key(user_table, &token)) {
            // Create a new SimpleMap for this token
            let chain_map = map::new<String, Map<String, u64>>();
            map::add(user_table, token, chain_map);
        };
        
        // Get the token's chain map
        let chain_map = map::borrow_mut(user_table, &token);
        
        // Check if chain exists in the chain map
        if (!map::contains_key(chain_map, &chain)) {
            let token_map = map::new<String, u64>();
            map::add(chain_map, chain, token_map);
        };
        
        // Return mutable reference to the u64 value
        let provider_map = map::borrow_mut(chain_map, &chain);

        // Check if provider exists in the provider map
        if (!map::contains_key(provider_map, &provider)) {
            map::add(provider_map, provider, 0);
        };

        let previous = map::borrow(provider_map, &chain);
        map::upsert(provider_map, copy provider, *previous+value);
    }

fun find_user_requests(
    tracker: &mut UserTracker, 
    owner: vector<u8>, 
    shared_storage_name: String, 
    sub_owner: vector<u8>, 
    token: String, 
    chain: String, 
    provider: String
): &mut vector<UnstakeRequest> {
    TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);

    // Level 1: Table (shared_storage_name)
    if (!table::contains(&tracker.unstake_requests, shared_storage_name)) {
        table::add(&mut tracker.unstake_requests, shared_storage_name, map::new<String, Map<String, Map<String, vector<UnstakeRequest>>>>());
    };
    let token_level_map = table::borrow_mut(&mut tracker.unstake_requests, shared_storage_name);

    // Level 2: Map (token)
    if (!map::contains_key(token_level_map, &token)) {
        map::add(token_level_map, token, map::new<String, Map<String, vector<UnstakeRequest>>>());
    };
    let chain_level_map = map::borrow_mut(token_level_map, &token);

    // Level 3: Map (chain)
    if (!map::contains_key(chain_level_map, &chain)) {
        map::add(chain_level_map, chain, map::new<String, vector<UnstakeRequest>>());
    };
    let provider_level_map = map::borrow_mut(chain_level_map, &chain);

    // Level 4: Map (provider) -> Vector
    if (!map::contains_key(provider_level_map, &provider)) {
        map::add(provider_level_map, provider, vector::empty<UnstakeRequest>());
    };

    map::borrow_mut(provider_level_map, &provider)
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

    fun calculate_total_vote_power(map: &Map<String, Map<String, Map<String, u64>>>): u256 {
        let total_vote_power: u256 = 0;
        let tokens = TokensType::return_full_nick_names_list();
        let i = 0;
        let token_count = vector::length(&tokens);

        while (i < token_count) {
            let token = vector::borrow(&tokens, i);
            
            if (map::contains_key(map, token)) {
                let token_map = map::borrow(map, token);
                let chains = map::keys(token_map);
                let j = 0;
                let chain_count = vector::length(&chains);

                let metadata = TokensMetadata::get_coin_metadata_by_symbol(*token);
                let metadata_denom = (TokensMetadata::get_coin_metadata_denom(&metadata) as u256);
                let tier_efficiency = (TokensMetadata::get_coin_metadata_tier_efficiency(&metadata) as u256);
                let price = (TokensMetadata::get_coin_metadata_price(&metadata) as u256);
                
                assert!(metadata_denom > 0, 25565);

                while (j < chain_count) {
                    let chain = vector::borrow(&chains, j);
                    let provider_map = map::borrow(token_map, chain);
                    let providers = map::keys(provider_map); // Call this ONCE
                    let h = 0;
                    let provider_count = vector::length(&providers);

                    while(h < provider_count) {
                        let provider = vector::borrow(&providers, h);
                        let value = (*map::borrow(provider_map, provider) as u256);

                        if (*token != utf8(b"Qiara")) {
                            let usd_value = value * price;
                            if (usd_value > 0) {
                                let x = usd_value / metadata_denom;
                                // Consider moving the /10000 outside or checking precision
                                let additional_power = staking_vote_weight(tier_efficiency, x);
                                total_vote_power = total_vote_power + (additional_power / 10000);
                            };
                        } else {
                            total_vote_power = total_vote_power + value;
                        };
                        h = h + 1;
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        total_vote_power
    }
// === VIEW FUNCTIONS === //
    #[view]
    public fun get_voting_power(shared_storage_name: String): u256 acquires UserTracker{
        let tracker = borrow_global<UserTracker>(@dev);

        if(!table::contains(&tracker.tracker, shared_storage_name)) {
            abort ERROR_USER_NOT_INITIALIZED
        };

        let user_map = table::borrow(&tracker.tracker, shared_storage_name);
        return calculate_total_vote_power(user_map)
    }
    #[view]
    public fun return_address_staked(shared_storage_name: String, token: String, chain: String): Map<String, u64> acquires UserTracker {

        let tracker = borrow_global<UserTracker>(@dev);

        if(!table::contains(&tracker.tracker, shared_storage_name)) {
             abort ERROR_USER_NOT_INITIALIZED
        };
        let user = table::borrow(&tracker.tracker, shared_storage_name);

        if(!map::contains_key(user, &token)) {
             abort ERROR_USER_DOESNT_STAKED_THIS_TOKEN_YET
        };

        let token_map = map::borrow(user, &token);

        if(!map::contains_key(token_map, &token)) {
             abort ERROR_USER_DOESNT_STAKED_THIS_TOKEN_YET
        };

        *map::borrow(token_map, &chain)
    }
}
