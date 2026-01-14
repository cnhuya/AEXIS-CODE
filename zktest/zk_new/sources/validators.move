module dev::QiaraVv1 {
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
    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_NOT_REGISTERED_VALIDATOR: u64 = 2;
    const ERROR_PARENT_VALIDATOR_ALREADY_REGISTERED: u64 = 3;
    const ERROR_NEW_PARENT_VALIDATOR_MUST_BE_IN_THE_VALIDATOR_REGISTRY: u64 = 4;
    const ERROR_INVALID_SIGNATURE: u64 = 1001;
    const ERROR_QUORUM_NOT_MET: u64 = 1002;
    const ERROR_STATE_NOT_FOUND: u64 = 1003;


    const N_VALIDATORS: u64 = 8;

    // === STRUCTS === //
    // list of all ACTIVE parents/relayers
    struct ActiveParents has key {
        map: Map<address, Parent>,
    }
    // list of all parents/relayers
    struct Parents has key {
        map: Map<address, Parent>,
    }
    struct Parent has key, store, copy, drop {
        pub_key: vector<u8>,
        self_staked: u64,
        total_stake: u64,
        isActive: bool,
        sub_validators: Map<address, u64>,
    }

    // list of all validators
    struct Validators has key {
        table: Table<address, ValidatorStake>,
    }
    // validator stake (global struct for both sub validators, and validators)
    struct ValidatorStake has key, store, copy, drop {
        parent: address,
        pub_key: vector<u8>,
        stake: u64,
    }

    // for zk proof
    struct ValidatorBody has key, store, copy, drop {
        pub_key: vector<u8>,
        staked: u64,
        index: u64, // Position in the 64-validator array (0-63)
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, Validators {table: table::new<address, ValidatorStake>()});
        move_to(admin, ActiveParents {map: Map::new<address, Parents>()});
        move_to(admin, Parents {map: Map::new<address, Parents>()});
    }

    // === LOGIC === //
    public entry fun test_save_validator(signer: &signer, parent: address, validator: address, pub_key: vector<u8>, stake: u64) acquires Validators {
        // 1. Use borrow_global_mut to allow modifications
        let config = borrow_global_mut<Validators>(@dev); 
        
        let body = ValidatorStake { parent: parent, pub_key: pub_key, stake: stake };
        
        // 2. Now &mut config.table is valid
        table::upsert(&mut config.table, validator, body);    
    }

    public entry fun test_change_validator_parent(signer: &signer, new_parent: address, validator: address) acquires Validators {
        let config = borrow_global_mut<Validators>(@dev); 

        if(!table::contains(&config.table, validator)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };

        let validator = table::borrow_mut(&mut config.table, validator);
        validator.parent = new_parent;
    }

    public entry fun test_register_parent_validator(signer: &signer, parent: address) acquires ActiveParents, Parents, Validators {

        // TODO: check if signer has permission to execute this function, which he can obtain from governance vote.

        let active_parents = borrow_global_mut<ActiveParents>(@dev); 
        let parents = borrow_global_mut<Parents>(@dev);
        let validators = borrow_global_mut<Validators>(@dev);

        reg_parent(validators, active_parents, parents, parent);

    }

    fun reg_parent(validators: &mut table<address, ValidatorStake>, active_parents: &mut Map<address, Parent>, parents: &mut Map<address, Parent>, parent: address){
        if(map::contains_key(&parents, &parent)) {
            abort ERROR_PARENT_VALIDATOR_ALREADY_REGISTERED
        };

        if(!table::contains(&validators, parent)) {
            abort ERROR_NEW_PARENT_VALIDATOR_MUST_BE_IN_THE_VALIDATOR_REGISTRY
        };

        let validator = table::borrow_mut(&mut validators, parent);
        let parent_struct = Parent { pub_key: validator.pub_key, self_staked: validator.staked, isActive: true, total_stake: 0, sub_validators: Map::new<address, u64>() };
        map::upsert(&mut parents, parent, parent_struct);

        check_active_parents(active_parents, parent_struct);
    }


    fun check_active_parents(active_parents: &mut Map<address, Parent>, parent: Parent) {
        let length = map::length(&active_parents);

        if(length < N_VALIDATORS) {
            map::upsert(&mut active_parents, parent, parent);
            return
        };

        while(length > 0) {
            let active_parent = map::borrow(&active_parents, length);
            if(active_parent.total_stake < parent.total_stake) {
                map::remove(&mut active_parents, length);
                map::upsert(&mut active_parents, parent, parent);
            };
            length = length - 1;
        }
    }


    fun reg_validator_for_parent(active_parents: &mut Map<address, Parent>, parents: &mut Map<address, Parent>, validators: &mut table<address, ValidatorStake>, parent: address,) {
        if(!table::contains(&validators, validator)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };

        let validator = table::borrow_mut(&mut config.table, validator);
        validator.parent = new_parent;

        let parent = map::borrow(&parents, parent);
        map::upsert(&mut parent.sub_validators, validator, validator.stake);
    }

    // TODO auto upate function when validator changes his stakes
    // this function needs to change the values in Validators, Parents and also somehow check if the parent is in ActiveParents

    #[view]
    public fun return_all_parents(): Map<address, Parent> acquires Parents {
        let vars = borrow_global<Parents>(@dev);
        vars.map 
    }

    #[view]
    public fun return_all_active_arents(): Map<address, Parent> acquires ActiveParents {
        let vars = borrow_global<ActiveParents>(@dev);
        vars.map 
    }

    #[view]
    public fun return_validator(val: address): Validator acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!table::contains(&vars.table, val)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };
        return *table::borrow(&vars.table, val);
    }


}