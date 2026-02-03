module dev::QiaraBridgeV8 {
    use std::signer;
    use supra_framework::account::{Self as address};
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info;
    use std::table:: {Self as table, Table};
    use std::timestamp;
    use std::bcs;
    use std::hash;
    use std::debug::print;
    use aptos_std::from_bcs;
    use aptos_std::ed25519::{Self as Crypto, Signature, UnvalidatedPublicKey};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use supra_framework::object::{Self, Object};
    use supra_framework::primary_fungible_store;
    use dev::QiaraEventV2::{Self as Event};
    use dev::QiaraStorageV2::{Self as storage};

    use dev::QiaraTokensCoreV4::{Self as TokensCore};
    use dev::QiaraTokensValidatorsV4::{Self as TokensValidators};
    use dev::QiaraTokensSharedV4::{Self as TokensShared};

    use dev::QiaraMarginV3::{Self as Margin};
    
    use dev::QiaraPayloadV8::{Self as Payload};
    use dev::QiaraValidatorsV8::{Self as Validators};
    /// Admin address constant
    const STORAGE: address = @dev;

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_VALIDATOR_IS_ALREADY_ALLOWED: u64 = 3;
    const ERROR_INVALID_CHAIN_TYPE_ARGUMENT: u64 = 4;
    const ERROR_CHAIN_ALREADY_REGISTERED: u64 = 5;
    const ERROR_NOT_VALIDATOR: u64 = 6;
    const ERROR_DUPLICATE_EVENT: u64 = 7;
    const ERROR_INVALID_BATCH_REGISTER_EVENT_ARG_EQUALS: u64 = 8;
    const ERROR_INVALID_SIGNATURE: u64 = 9;
    const ERROR_INVALID_MESSAGE: u64 = 10;
    const ERROR_NOT_FOUND: u64 = 11;
    const ERROR_CAPS_NOT_PUBLISHED: u64 = 11;
    const ERROR_NOT_ENOUGH_VOTING_POWER: u64 = 12;


// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    // Permissions 
    struct Permissions has key {
    }

// === STRUCTS === //
   // [DEPRECATED]
   // struct DepositEvent has store, key {}
   // struct RequestUnlockEvent has store, key {}
   // struct UnlockEvent has store, key {}

    /// In the future implement a more complext structure for storage,
    /// Making it generic for epoch (1 day for example) and adding epoch key to events, to make it
    /// so that event from epoch (ex. 14797) cant be stored/registered/validated in epoch (ex. 14798)
    /// This way we can avoid double spending attacks on other chains and also reduce storage space 
    /// which would mean more efficiency and lower gas fees by around 30-40%.

   /// counting how many times the message was "validated"
   /// If lets say it was "validated" total of 5 times succesfully, the 6th times will mote if from here
   /// to chain storage
   /// 
   /// <message> <vector<Aux>>
   /// <message> <validators, weight>
   /// <message> <validator adress, validator weight, <weight>>
   
// === Pending Struct Methology === //
    struct Pending has key {
        main: Table<vector<u8>, MainVotes>,
        zk: Table<vector<u8>, ZkVotes>,
    }

    struct Validated has key {
        main: Table<vector<u8>, MainVotes>,
        zk: Table<vector<u8>, ZkVotes>,
    }

    struct Vote has key, copy, store, drop {
        weight: u128,
        signature: vector<u8>,
    }

    struct ZkVote has key, copy, store, drop {
        weight: u128,
        s_r8x: String,
        s_r8y: String,
        s: String,
        pub_key_x: String,
        pub_key_y: String,
        index: u16,
    }

    struct MainVotes has key, copy, store, drop {
        votes: Map<address, Vote>,
        rv: vector<address>, // rewarded validators
        total_weight: u128,
    }
    struct ZkVotes has key, copy, store, drop {
        votes: Map<address, ZkVote>,
        rv: vector<address>, // rewarded validators
        total_weight: u128,
    }

// === EVENTS === //

/*    #[event]
    struct BridgeUpdateEvent has drop, store {
        message: String,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        sigs: Map<address, ZkVote>,
        total_vote_power: u64,
        time: u64,
    }

    #[event]
    struct VoteEvent has drop, store {
        validator: address,
        message: String,
        root: String,
        vote_power: u64,
        total_vote_power: u64,
        time: u64,
    }*/

// === INIT === //
    fun init_module(admin: &signer) {
    //    if (!exists<Permissions>(@dev)) {
    //        let _cap = Permissions { vault_access: Vaults::give_access(admin), coin_access: CoinDeployer::give_access(admin)};
    //        move_to(admin, _cap);
    //    };
    }

// === FUNCTIONS === //
   
/*    #[view]
    public fun return_validator_raw(val: String): (String, String, vector<u8>, u256, u256, bool, Map<String, u256>) acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        let validator  = map::borrow(&vars.map, &val);
        return (validator.pub_key_x, validator.pub_key_y,validator.pub_key, validator.self_power, validator.total_power, validator.isActive, validator.sub_validators)
*/
    public entry fun register_event(validator: &signer, shared_storage_name: String, owner: vector<u8>, type_names: vector<String>, payload: vector<vector<u8>>) acquires Pending, Validated, Permissions {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(validator)));
        Payload::ensure_valid_payload(type_names, payload);
        let (_, hash) = Payload::find_payload_value(utf8(b"hash"), type_names, payload);
        let (_, type) = Payload::find_payload_value(utf8(b"type"), type_names, payload);
        let (_, event_type) = Payload::find_payload_value(utf8(b"event_type"), type_names, payload);
        let (pub_key_x, pub_key_y, pubkey, _, _, _, _) = Validators::return_validator_raw(shared_storage_name);
        let message = Payload::unpack_payload(payload);


        let pending = borrow_global_mut<Pending>(STORAGE);
        let validated = borrow_global_mut<Validated>(STORAGE);

        // Store event in both pending and chain storage
        if(type == b"main"){

            let (_, _signature) = Payload::find_payload_value(utf8(b"signature"), type_names, payload);
            let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(pubkey);
            let signature = Crypto::new_signature_from_bytes(from_bcs::to_bytes(_signature));
            let verified = Crypto::signature_verify_strict(&signature, &pubkey_struct, message);
            assert!(verified, ERROR_INVALID_SIGNATURE);

            handle_main_event(
                validator,
                (signer::address_of(validator)),
                &mut pending.main,
                &mut validated.main,
                hash,
                payload,
                _signature,
                shared_storage_name,
                from_bcs::to_string(event_type)
            );
        } else if (type == b"zk"){
            handle_zk_event(
                validator,
                (signer::address_of(validator)),
                &mut pending.zk,
                &mut validated.zk,
                hash,
                payload,
                build_zkVote_from_payload(pub_key_x, pub_key_y, type_names, payload),
                shared_storage_name,
                from_bcs::to_string(event_type)

            );
        };


    }

    fun build_zkVote_from_payload(pubkwey_x: String, pubkey_y: String, type_names: vector<String>, payload: vector<vector<u8>>): ZkVote {
        let (_, s_r8x) = Payload::find_payload_value(utf8(b"s_r8x"), type_names, payload);
        let (_, s_r8y) = Payload::find_payload_value(utf8(b"s_r8x"), type_names, payload);
        let (_, s) = Payload::find_payload_value(utf8(b"s_r8x"), type_names, payload);
        let (_, index) = Payload::find_payload_value(utf8(b"s_r8x"), type_names, payload);

        return ZkVote {
            weight: 0,
            s_r8x: from_bcs::to_string(s_r8x), //s_r8x,
            s_r8y: from_bcs::to_string(s_r8y), //s_r8y,
            s:  from_bcs::to_string(s), //s_r8y,
            pub_key_x: pubkwey_x,
            pub_key_y: pubkey_y,
            index:  from_bcs::to_u16(s), //s_r8y,
        }
    }

    fun check_validator_validation(validator: address, map: Map<address, Vote>): (bool, u128){
        if(map::contains_key(&map, &validator)){
            let v = map::borrow(&map, &validator);
            return (true, v.weight)
        };
        return (false, 0)
    }


    fun check_validator_validation_zk(validator: address, map: Map<address, ZkVote>): (bool, u128){
        if(map::contains_key(&map, &validator)){
            let v = map::borrow(&map, &validator);
            return (true, v.weight)
        };
        return (false, 0)
    }

    fun check_rewarded_validators(vect: &mut vector<address>, validator: address){
        let len = vector::length(vect);

        let max_len = storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MAXIMUM_REWARDED_VALIDATORS")));
        if(len < (max_len as u64)){ // if there is still left capacity for another rewarded validator
            vector::push_back(vect, validator);
            return;
        };

        let i = 0;
        while (i < vector::length(vect)) {
            let r_validator = vector::borrow(vect, i);
            let last_reward_index = TokensValidators::return_validator_last_reward(*r_validator);
            let validator_last_reward = TokensValidators::return_validator_last_reward(validator);
            
            if (last_reward_index > validator_last_reward) {
                // First release the borrow by ending this scope
                // Then remove and insert
                let new_vect = vect;
                vector::remove(new_vect, i);
                vector::insert(new_vect, i, validator);
                vect = new_vect;
                return
            };
            i = i + 1;
        }
    }

    fun ensure_unique_validators(vect: vector<address>): bool{
        let len = vector::length(&vect);

        let xv = vector::empty<address>();

        let min_uniq_validators = storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS")));
        while(len>0){
            if(vector::length(&xv) < (min_uniq_validators as u64)){
                let validator = vector::borrow(&vect, len-1);
                if(!vector::contains(&xv, validator)){
                    vector::push_back(&mut xv, *validator);
                };
            } else{
                return true
            };
            len=len-1;
        };
        return false
    }


    fun handle_main_event(signer: &signer, validator: address, pending_table: &mut table::Table<vector<u8>, MainVotes>, validated_table: &mut table::Table<vector<u8>, MainVotes>, hash: vector<u8>, payload: vector<vector<u8>>, signature: vector<u8>, shared_storage_name: String, event_type: String ) acquires Permissions {
        let quorum = storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT")));
        // Already validated?
        if (table::contains(validated_table, hash)) {
            abort(ERROR_DUPLICATE_EVENT);
        };
        let (_, _, _, _, _, _, _, _, vote_weight, _, _) = Margin::get_user_total_usd(shared_storage_name);
        assert!(vote_weight > (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTING_POWER"))) as u256), ERROR_NOT_ENOUGH_VOTING_POWER);
        // Update pending validators
        let count = if (table::contains(pending_table, hash)) {
            let votes = table::borrow_mut(pending_table, hash);
            let (did_validate, existing_weight) = check_validator_validation(validator, votes.votes);

            // If validator did not validate this tx yet, add them
            if (!did_validate) {
                let vote = Vote { signature: signature, weight: (vote_weight as u128) };
                map::add(&mut votes.votes, validator, vote);
                check_rewarded_validators(&mut votes.rv, validator);
                
                // Update total weight
                votes.total_weight = votes.total_weight + (vote_weight as u128);
                
                let data = vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
                    Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"hash"), utf8(b"vector<u8>"), bcs::to_bytes(&hash)),
                    Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ];
                Event::emit_market_event(utf8(b"Vote Event"), data);

                // Return updated total weight
                votes.total_weight


            } else {
                // If validator already voted, check if we have enough unique validators
                let enough_validators = ensure_unique_validators(map::keys(&votes.votes));
                if (!enough_validators) {
                    1  // Not enough validators yet
                } else {
                    // Return current total weight if validator already voted and we have enough validators
                    votes.total_weight
                }
            }
        } else {
            // First vote for this message
            let validator_vote = Vote {signature: signature, weight: (vote_weight as u128)};
            let vect = vector[validator];
            let map = map::new<address, Vote>();
            map::add(&mut map, validator, validator_vote);
            let votes = MainVotes {votes: map, rv: vect, total_weight: (vote_weight as u128)};
            table::add(pending_table, copy hash, votes);
            1 
        };

        // Promote to validated
        if (count >= (quorum as u128)) {
            // Defensive: ensure key exists before remove
            assert!(table::contains(pending_table, hash), ERROR_NOT_FOUND);
            let votes_from_pending = table::remove(pending_table, hash);

            if (table::contains(validated_table, hash)) {
                abort(ERROR_DUPLICATE_EVENT);
            };
            table::add(validated_table, hash, votes_from_pending);

            assert!(exists<Permissions>(@dev), ERROR_CAPS_NOT_PUBLISHED);
            let cap = borrow_global<Permissions>(@dev);
            if(event_type == utf8(b"Deposit")){
              //  let coins = CoinDeployer::extract_to<E>(signer, _coin_cap, user_addr, amount);
            //    Vaults::bridge_deposit<E,T,X>(signer, &cap.vault_access, _user_cap, user_addr, amount, coins, lend_rate, borrow_rate);
            } else if(event_type == utf8(b"Request Unlock")){
            //   Vaults::request_unlock<E>(signer, user_addr, amount, &_user_cap);
            } else if(event_type == utf8(b"Unlock")){
            //   Vaults::unlock<E>(signer, user_addr, amount, &_user_cap);
            }  else{
                abort(ERROR_INVALID_MESSAGE);
            };

            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
                Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&count)),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&count)),
                Event::create_data_struct(utf8(b"quorum"), utf8(b"vector<u8>"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_market_event(utf8(b"Validate Event"), data);
            };
    }
    fun handle_zk_event(signer: &signer, validator: address, pending_table: &mut table::Table<vector<u8>, ZkVotes>, validated_table: &mut table::Table<vector<u8>, ZkVotes>, hash: vector<u8>, payload: vector<vector<u8>>, zk_vote: ZkVote, shared_storage_name: String, event_type: String ) acquires Permissions {
        let quorum = storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT")));

        // Already validated?
        if (table::contains(validated_table, hash)) {
            abort(ERROR_DUPLICATE_EVENT);
        };
        let (_, _, _, _, _, _, _, _, vote_weight, _, _) = Margin::get_user_total_usd(shared_storage_name);
        assert!(vote_weight > (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTING_POWER"))) as u256), ERROR_NOT_ENOUGH_VOTING_POWER);
        // Update pending validators
        let count = if (table::contains(pending_table, hash)) {
            let votes = table::borrow_mut(pending_table, hash);
            let (did_validate, existing_weight) = check_validator_validation_zk(validator, votes.votes);

            // If validator did not validate this tx yet, add them
            if (!did_validate) {
                zk_vote.weight = (vote_weight as u128);
                map::add(&mut votes.votes, validator, zk_vote);
                check_rewarded_validators(&mut votes.rv, validator);
                
                // Update total weight
                votes.total_weight = votes.total_weight + (vote_weight as u128);
                
                let data = vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
                    Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"hash"), utf8(b"vector<u8>"), bcs::to_bytes(&hash)),
                    Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ];
                Event::emit_market_event(utf8(b"Vote Event"), data);

                // Return updated total weight
                votes.total_weight
            } else {
                // If validator already voted, check if we have enough unique validators
                let enough_validators = ensure_unique_validators(map::keys(&votes.votes));
                if (!enough_validators) {
                    1  // Not enough validators yet
                } else {
                    // Return current total weight if validator already voted and we have enough validators
                    votes.total_weight
                }
            }
        } else {
            // First vote for this message
            zk_vote.weight = (vote_weight as u128);
            let vect = vector[validator];
            let map = map::new<address, ZkVote>();
            map::add(&mut map, validator, zk_vote);
            let votes = ZkVotes {votes: map, rv: vect, total_weight: (vote_weight as u128)};
            table::add(pending_table, copy hash, votes);

            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
                Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"hash"), utf8(b"vector<u8>"), bcs::to_bytes(&hash)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_market_event(utf8(b"Register Event"), data);
            1 
        };

        // Promote to validated
        if (count >= (quorum as u128)) {
            // Defensive: ensure key exists before remove
            assert!(table::contains(pending_table, hash), ERROR_NOT_FOUND);
            let votes_from_pending = table::remove(pending_table, hash);

            if (table::contains(validated_table, hash)) {
                abort(ERROR_DUPLICATE_EVENT);
            };
            table::add(validated_table, hash, votes_from_pending);

            assert!(exists<Permissions>(@dev), ERROR_CAPS_NOT_PUBLISHED);
            let cap = borrow_global<Permissions>(@dev);
            if(event_type == utf8(b"Deposit")){
              //  let coins = CoinDeployer::extract_to<E>(signer, _coin_cap, user_addr, amount);
            //    Vaults::bridge_deposit<E,T,X>(signer, &cap.vault_access, _user_cap, user_addr, amount, coins, lend_rate, borrow_rate);
            } else if(event_type == utf8(b"Request Unlock")){
            //   Vaults::request_unlock<E>(signer, user_addr, amount, &_user_cap);
            } else if(event_type == utf8(b"Unlock")){
            //   Vaults::unlock<E>(signer, user_addr, amount, &_user_cap);
            }  else{
                abort(ERROR_INVALID_MESSAGE);
            };
        //    let _validators = copy validators;
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
                Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"hash"), utf8(b"vector<u8>"), bcs::to_bytes(&hash)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_market_event(utf8(b"Register Event"), data);
        };
    }



  /*  #[view]
    public fun is_validated(messages: vector<vector<u8>>): vector<bool> acquires Validated {
        let validated = borrow_global<Validated>(@dev);

        let results = vector::empty<bool>();
        let len = vector::length(&messages);
        let i = 0;

        while (i < len) {
            let message = vector::borrow(&messages, i);
            if (table::contains(&validated.txs, *message)) {
                vector::push_back(&mut results, true);
            } else {
                vector::push_back(&mut results, false);
            };
            i = i + 1;
        };

        results
    }*/



    fun convert_eventID_to_string(eventID: u8): String{
        if(eventID == 1 ){
            return utf8(b"Deposit")
        } else if(eventID == 2 ){
            return utf8(b"Request Unlock")
        } else if(eventID == 3 ){
            return utf8(b"Unlock")
        } else{
            return utf8(b"Unknown")
        }
    }



    #[test(account = @0x1, owner = @0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd, owner2 = @0x281d0fce12a353b1f6e8bb6d1ae040a6deba248484cf8e9173a5b428a6fb74e7)]
    public entry fun test(account: signer, owner: signer, owner2: signer) acquires  Chain, Pending, Validated, Caps{
        // Initialize the CurrentTimeMicroseconds resource
        supra_framework::timestamp::set_time_has_started_for_testing(&account);
        supra_framework::timestamp::update_global_time_for_test(50000);
        let t1 =  supra_framework::timestamp::now_seconds();
        print(&t1);
        // Initialize the module
        init_module(&owner);
        // Change config
        let addr = signer::address_of(&owner);
        let addr2 = signer::address_of(&owner2);
        // Register a new chain
       // register_chain<Sui>(&owner, 1, utf8(b"Sui"), utf8(b"SUI"));
       // register_chain<Base>(&owner, 2, utf8(b"Base"), utf8(b"BASE"));
       // register_chain<Supra>(&owner, 3, utf8(b"Supra"), utf8(b"SUPRA"));           

        // Allow a validator


        let pubkey: vector<u8> = vector[
            0xbe, 0x4e, 0x29, 0x0a, 0x50, 0x82, 0xe6, 0xeb,
            0x0d, 0x01, 0x64, 0x1c, 0x4d, 0x35, 0x39, 0xf7,
            0x42, 0x33, 0x05, 0xac, 0xd9, 0x47, 0x42, 0xa0,
            0xe6, 0x23, 0x88, 0x2c, 0xae, 0x3d, 0x1d, 0xfd
        ];

        let pubkey2: vector<u8> = vector[
            0xd2, 0xf4, 0x24, 0x47, 0x42, 0xc8, 0x17, 0x76,
            0x50, 0x3b, 0x8e, 0x45, 0xc4, 0xba, 0x6f, 0x7e,
            0x87, 0x8d, 0x96, 0xe0, 0xd9, 0x74, 0xef, 0x51,
            0x6b, 0x99, 0x25, 0x09, 0xeb, 0x08, 0x5b, 0xcd
        ];

    let serialized_signature: vector<u8> = vector[
        0xfc, 0x3c, 0xa9, 0x97, 0x1c, 0x22, 0x62, 0x60,
        0x4c, 0xd4, 0xe0, 0xda, 0x9d, 0xa2, 0xa7, 0x87,
        0x5b, 0x3a, 0x15, 0x61, 0xd6, 0x32, 0x9b, 0x68,
        0xbf, 0xc1, 0x47, 0xb6, 0x75, 0xbc, 0xc5, 0x2d,
        0xa6, 0xe7, 0x9b, 0x40, 0x9e, 0xa9, 0x50, 0x90,
        0xfc, 0x36, 0x97, 0xd6, 0xdf, 0xcd, 0x22, 0x2f,
        0x36, 0xec, 0x71, 0x9d, 0xd7, 0xdd, 0x09, 0xf8,
        0x1f, 0x4f, 0x5e, 0xa5, 0xb1, 0x69, 0x3b, 0x02
    ];

    let serialized_payload: vector<u8> = vector[
        0x01, 0x51, 0x5b, 0xbf, 0xb8, 0x77, 0x80, 0x44,
        0xab, 0x8f, 0xa5, 0x39, 0x3f, 0x89, 0x84, 0x4e,
        0x5e, 0x27, 0x45, 0x44, 0x45, 0xc7, 0xc6, 0x5a,
        0x91, 0x5e, 0x60, 0x28, 0xdf, 0x40, 0x2d, 0x50,
        0x82, 0x65, 0xad, 0x96, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xcd, 0xde, 0x99, 0x47, 0x1a, 0x73,
        0x41, 0xc7, 0x3d, 0x3c, 0x78, 0xa2, 0x12, 0x8f,
        0x16, 0xff, 0x82, 0x74, 0x12, 0x52, 0xbb, 0xb7,
        0x89, 0xe9, 0x36, 0x8d, 0x98, 0x37, 0x9e, 0x2b,
        0x8c, 0xdd
    ];


        allow_validator<Base>(&owner, addr, pubkey);
        allow_validator<Supra>(&owner, addr, pubkey);
        allow_validator<Sui>(&owner, addr, pubkey);

        allow_validator<Base>(&owner, addr2, pubkey2);
        allow_validator<Supra>(&owner, addr2, pubkey2);
        allow_validator<Sui>(&owner, addr2, pubkey2);


        let validators = get_chain_validators<Sui>();  

        print(&utf8(b" VALIDATORS "));
        print(&validators);
       // print(&vector::length(&serialized_signature));

      //  struct eth has drop, store {}

        register_event<Sui,Sui>(&owner, serialized_signature , serialized_payload); 

        register_event<Sui,Sui>(&owner2, serialized_signature , serialized_payload);           
 //       print(&deserialize_message(&serialized_payload));

    }
}

