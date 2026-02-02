module dev::QiaraValidatorsV2 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::ed25519;
    use aptos_std::table::{Self, Table};
    //use aptos_std::any::{Self, Any};
    use supra_framework::event;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{Self as String, String, utf8};

    use dev::QiaraTokensSharedV3::{Self as TokensShared};

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
        move_to(admin, ActiveValidators {list: vector::empty<String>()});
        move_to(admin, Validators {map: map::new<String, Validator>()});
        if (!exists<Stakers>(@dev)) {
            move_to(admin, Stakers { table: table::new<String, String>() });
        };
    }

// === PUBLIC FUNCTIONS === //

    public fun register_validator(signer: &signer, shared_storage_name: String, owner: vector<u8>, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>, power:u256, perm: Permission) acquires ActiveValidators, Validators {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(power,&mut active_validators.list, &mut validators.map, shared_storage_name, pub_key_x, pub_key_y, pub_key);

    }

    public fun change_validator_poseidon_pubkeys(signer: &signer,  shared_storage_name: String, owner: vector<u8>, pub_key_x: String, pub_key_y: String, perm: Permission) acquires Validators {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared_storage_name)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared_storage_name);
        validator.pub_key_x = pub_key_x;
        validator.pub_key_y = pub_key_y;
    }

    public fun change_validator_pubkey(signer: &signer, shared_storage_name: String, owner: vector<u8>, pub_key: vector<u8>, perm: Permission) acquires Validators {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared_storage_name)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared_storage_name);
        validator.pub_key = pub_key;
    }

    public fun change_staker_validator(signer: &signer, shared_storage_name: String, owner: vector<u8>, new_validator: String, perm: Permission) acquires ActiveValidators, Validators, Stakers {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, bcs::to_bytes(&signer::address_of(signer)));
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
            check_active_validators(&mut validators.map, &mut active_validators.list, new_validator);
        }
    }
    
    public fun return_updated_validator(validator: Validator, self_power: u256, total_power: u256): Validator{
        let new_validator = validator;
        new_validator.self_power = self_power;
        new_validator.total_power = total_power;
        new_validator
    }
    

// === INTERNAL FUNCTIONS === //
    fun reg_validator(power: u256, active_validators: &mut vector<String>, validators: &mut Map<String, Validator>, validator: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>) {
        if(map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_ALREADY_REGISTERED
        };

        let validator_struct = Validator { pub_key: pub_key, pub_key_x: pub_key_x, pub_key_y: pub_key_y, self_power: power, isActive: true, last_active: 0, total_power: power, sub_validators: map::new<String, u256>() };
        map::upsert(validators, validator, validator_struct);

        check_active_validators(validators,active_validators, validator);
    }

    fun check_active_validators(validators: &Map<String, Validator>, active_validators: &mut vector<String>, validator: String) {
        let length = vector::length(active_validators);

        if(length < 16) {
            vector::push_back(active_validators, validator);
            return
        };

        while(length > 0) {
            let validator_addr = vector::borrow(active_validators, length);
            let active_validator = obtain_validator(validators, *validator_addr);
            let self_validator = obtain_validator(validators, validator);
            if(active_validator.total_power < self_validator.total_power) {
                vector::remove(active_validators, length);
                vector::push_back(active_validators, validator);
            };
            length = length - 1;
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
    public fun return_all_active_arents(): vector<String> acquires ActiveValidators {
        let vars = borrow_global<ActiveValidators>(@dev);
        vars.list 
    }

    #[view]
    public fun return_all_active_validators_full(): Map<String, Validator> acquires ActiveValidators, Validators {
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
        map 
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