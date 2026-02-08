module dev::QiaraValidatorsV20 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::ed25519;
    use aptos_std::table::{Self, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{Self as String, String, utf8};

    use dev::QiaraEventV5::{Self as Event};
    use dev::QiaraTokensSharedV7::{Self as TokensShared};
    use dev::QiaraMarginV6::{Self as Margin};

    use dev::QiaraGenesisV20::{Self as Genesis};
    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_VALIDATOR_ALREADY_REGISTERED: u64 = 2;
    const ERROR_VALIDATOR_DOESNT_EXISTS: u64 = 3;
    const ERROR_NOT_REGISTERED_VALIDATOR: u64 = 4;
    const ERROR_NOT_STAKER: u64 = 5;

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
    // list of all ACTIVE validators/relayers
    struct ActiveValidators has key {
        list: vector<String>,
        root: String,
        epoch: u64,
    }
    // list of all validators/relayers
    struct Validators has key {
        map: Map<String, Validator>,
    }
    struct Validator has key, store, copy, drop {
        pub_key_y: String,
        pub_key_x: String,
        pub_key: vector<u8>,
        self_power: u256,
        total_power: u256,
        isActive: bool,
        last_active: u64,
        sub_validators: Map<String, u256>,
    }

    struct Stakers has key, store {
        table: Table<String, String>,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, ActiveValidators {list: vector::empty<String>(), root: utf8(b""), epoch: 0});
        move_to(admin, Validators {map: map::new<String, Validator>()});
        if (!exists<Stakers>(@dev)) {
            move_to(admin, Stakers { table: table::new<String, String>() });
        };
    }

// === PUBLIC FUNCTIONS === //

    public entry fun dev_register_validator(signer: &signer, validator: vector<u8>, shared_storage_name: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>, power:u256) acquires ActiveValidators, Validators {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_ADMIN);
        TokensShared::assert_is_owner(validator, shared_storage_name);
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(power,active_validators, &mut validators.map, shared_storage_name, pub_key_x, pub_key_y, pub_key);

    }

    // Interface for users/validators
    public entry fun register_validator(signer: &signer, shared_storage_name: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>, power:u256) {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(utf8(b"pub_key_x"), utf8(b"string"), bcs::to_bytes(&pub_key_x)),
            Event::create_data_struct(utf8(b"pub_key_y"), utf8(b"string"), bcs::to_bytes(&pub_key_y)),
            Event::create_data_struct(utf8(b"pub_key"), utf8(b"vector<u8>"), bcs::to_bytes(&pub_key)),
            Event::create_data_struct(utf8(b"power"), utf8(b"u256"), bcs::to_bytes(&power)),
        ];
        Event::emit_consensus_event(utf8(b"Register Validator"), data, utf8(b"zk"));

    }
    public entry fun re_check_active_validators(signer: &signer){
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
        ];
        Event::emit_consensus_event(utf8(b"Re-check Active Validators"), data, utf8(b"zk"));

    }
    public entry fun change_staker_validator(signer: &signer, shared_storage_name: String, new_validator: String){
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(utf8(b"new_validator"), utf8(b"string"), bcs::to_bytes(&new_validator)),
        ];
        Event::emit_consensus_event(utf8(b"Change Staker Validator"), data, utf8(b"zk"));

    }
    public entry fun change_validator_poseidon_pubkeys(signer: &signer,  shared_storage_name: String, pub_key_x: String, pub_key_y: String) {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(utf8(b"pub_key_x"), utf8(b"string"), bcs::to_bytes(&pub_key_x)),
            Event::create_data_struct(utf8(b"pub_key_y"), utf8(b"string"), bcs::to_bytes(&pub_key_y)),
        ];
        Event::emit_consensus_event(utf8(b"Change Validator Poseidon Pubkeys"), data, utf8(b"zk"));
    }
    public entry fun change_validator_pubkey(signer: &signer, shared_storage_name: String, pub_key: vector<u8>) {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage_name"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(utf8(b"pub_key"), utf8(b"string"), bcs::to_bytes(&pub_key)),
        ];
        Event::emit_consensus_event(utf8(b"Change Validator Pubkey"), data, utf8(b"zk"));
    }

    // Interface for consensus
    public fun c_register_validator(signer: &signer, shared_storage_name: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>, power:u256, perm: Permission) acquires ActiveValidators, Validators {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(power,active_validators, &mut validators.map, shared_storage_name, pub_key_x, pub_key_y, pub_key);

    }
    public fun c_re_check_active_validators(signer: &signer, perm: Permission) acquires ActiveValidators, Validators {
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        check_active_validators(&validators.map, active_validators);

    }
    public fun c_change_staker_validator(signer: &signer, shared_storage_name: String, new_validator: String, perm: Permission) acquires ActiveValidators, Validators, Stakers {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
        let stakers = borrow_global_mut<Stakers>(@dev);

        if(!table::contains(&stakers.table, shared_storage_name)) {
            abort ERROR_NOT_STAKER
        };

        if(!map::contains_key(&validators.map, &new_validator)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };

        let staker = table::borrow_mut(&mut stakers.table, shared_storage_name);
        table::upsert(&mut stakers.table, shared_storage_name, new_validator);

        let validator = map::borrow_mut(&mut validators.map, &new_validator);
        if(validator.isActive) {
            check_active_validators(&validators.map, active_validators);
        }
    }
    public fun c_change_validator_poseidon_pubkeys(signer: &signer,  shared_storage_name: String, pub_key_x: String, pub_key_y: String, perm: Permission) acquires Validators {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared_storage_name)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared_storage_name);
        validator.pub_key_x = pub_key_x;
        validator.pub_key_y = pub_key_y;
    }
    public fun c_change_validator_pubkey(signer: &signer, shared_storage_name: String, pub_key: vector<u8>, perm: Permission) acquires Validators {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(signer)), shared_storage_name);
        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared_storage_name)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared_storage_name);
        validator.pub_key = pub_key;
    }
    public fun c_update_root(signer: &signer, new_root: String, perm: Permission) acquires ActiveValidators {
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        active_validators.root = new_root;
    }

// === INTERNAL FUNCTIONS === //
    fun reg_validator(power: u256, active_validators: &mut ActiveValidators, validators: &mut Map<String, Validator>, validator: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>) {
        if(map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_ALREADY_REGISTERED
        };

        let validator_struct = Validator { pub_key: pub_key, pub_key_x: pub_key_x, pub_key_y: pub_key_y, self_power: power, isActive: true, last_active: 0, total_power: power, sub_validators: map::new<String, u256>() };
        map::upsert(validators, validator, validator_struct);

        check_active_validators(validators, active_validators);
    }

    fun check_active_validators(validators_map: &Map<String, Validator>, active_validators: &mut ActiveValidators) {
        let max_active = 16;
        let validators = map::keys(validators_map);
        let old_validators = active_validators.list;
        let epoch = Genesis::return_epoch();

        if((epoch as u64) == active_validators.epoch) {
            return
        };
        let total_count = vector::length(&validators);
        
        let top_validator_addrs = vector::empty<String>();
        let i = 0;

        while (i < total_count) {
            let name = *vector::borrow(&validators, i);
            
            let (_, _, _, _, _, _, _, _, current_power, _, _) = Margin::get_user_total_usd(name);

            let j = 0;
            let inserted = false;
            let top_len = vector::length(&top_validator_addrs);

            while (j < top_len) {
                let existing_name = *vector::borrow(&top_validator_addrs, j);
                
                let (_, _, _, _, _, _, _, _, existing_power, _, _) = Margin::get_user_total_usd(existing_name);

                if (current_power > existing_power) {
                    vector::insert(&mut top_validator_addrs, j, name);
                    inserted = true;
                    break
                };
                j = j + 1;
            };

            if (!inserted && top_len < max_active) {
                vector::push_back(&mut top_validator_addrs, name);
            };

            if (vector::length(&top_validator_addrs) > max_active) {
                vector::pop_back(&mut top_validator_addrs);
            };

            i = i + 1;
        };
        if(old_validators != top_validator_addrs) {
           active_validators.list = top_validator_addrs;

            let data = vector[];
            Event::emit_consensus_event(utf8(b"Active Validators Changed"), data, utf8(b"zk"));
           
        }
    }

    fun obtain_validator(validators: &Map<String, Validator>, validator: String): Validator {
        if(!map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        *map::borrow(validators, &validator)
    }
// === VIEW FUNCTIONS === //
    #[view]
    public fun return_all_validators(): Map<String, Validator> acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        vars.map 
    }

    #[view]
    public fun return_all_active_parents(): vector<String> acquires ActiveValidators {
        let vars = borrow_global<ActiveValidators>(@dev);
        vars.list 
    }

    #[view]
    public fun return_all_active_validators_full(): (Map<String, Validator>, u64) acquires ActiveValidators, Validators {
        let vars = borrow_global<ActiveValidators>(@dev);
        let validators = borrow_global<Validators>(@dev);
        let map = map::new<String, Validator>();

        let length = vector::length(&vars.list);
        while(length > 0) {
            let validator_addr = vector::borrow(&vars.list, length-1);
            let validator = return_validator(*validator_addr);
            map::add(&mut map, *validator_addr, validator);
            length = length - 1;
        };
        (map, vars.epoch)
    }

    #[view]
    public fun return_validator(val: String): Validator acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        return *map::borrow(&vars.map, &val)
    }

    #[view]
    public fun return_validator_raw(val: String): (String, String, vector<u8>, u256, u256, bool, Map<String, u256>) acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        let validator  = map::borrow(&vars.map, &val);
        return (validator.pub_key_x, validator.pub_key_y,validator.pub_key, validator.self_power, validator.total_power, validator.isActive, validator.sub_validators)
    }

}