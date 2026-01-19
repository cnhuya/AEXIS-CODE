module dev::QiaraVv8 {
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
    const ERROR_PARENT_DOESNT_EXISTS: u64 = 5;
    const ERROR_INVALID_SIGNATURE: u64 = 1001;
    const ERROR_QUORUM_NOT_MET: u64 = 1002;
    const ERROR_STATE_NOT_FOUND: u64 = 1003;


    const N_VALIDATORS: u64 = 8;

    // === STRUCTS === //
    // list of all ACTIVE parents/relayers
    struct ActiveParents has key {
        list: vector<address>,
    }
    // list of all parents/relayers
    struct Parents has key {
        map: Map<address, Parent>,
    }
    struct Parent has key, store, copy, drop {
        pub_key_y: String,
        pub_key_x: String,
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
        stake: u64,
    }


    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, Validators {table: table::new<address, ValidatorStake>()});
        move_to(admin, ActiveParents {list: vector::empty<address>()});
        move_to(admin, Parents {map: map::new<address, Parent>()});
    }

    // === LOGIC === //

    public entry fun change_parent_pubkey(signer: &signer, parent: address, pub_key_x: String, pub_key_y: String) acquires Parents {
        // 1. Use borrow_global_mut to allow modifications
        let parents = borrow_global_mut<Parents>(@dev); 
        
        if(!map::contains_key(&mut parents.map, &parent)) {
            abort ERROR_PARENT_DOESNT_EXISTS
        };

        let parent = map::borrow_mut(&mut parents.map, &parent);
        parent.pub_key_x = pub_key_x;
        parent.pub_key_y = pub_key_y;
    }

    public entry fun test_save_validator(signer: &signer, parent: address, validator: address, stake: u64) acquires Validators {
        // 1. Use borrow_global_mut to allow modifications
        let config = borrow_global_mut<Validators>(@dev); 
        
        let body = ValidatorStake { parent: parent, stake: stake };
        
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

    public entry fun test_register_parent_validator(signer: &signer, parent: address, pub_key_x: String, pub_key_y: String) acquires ActiveParents, Parents, Validators {

        // TODO: check if signer has permission to execute this function, which he can obtain from governance vote.

        let active_parents = borrow_global_mut<ActiveParents>(@dev); 
        let parents = borrow_global_mut<Parents>(@dev);
        let validators = borrow_global_mut<Validators>(@dev);

        reg_parent(&mut validators.table, &mut active_parents.list, &mut parents.map, parent, pub_key_x, pub_key_y);

    }

    fun reg_parent(validators: &mut Table<address, ValidatorStake>, active_parents: &mut vector<address>, parents: &mut Map<address, Parent>, parent: address, pub_key_x: String, pub_key_y: String) {
        if(map::contains_key(parents, &parent)) {
            abort ERROR_PARENT_VALIDATOR_ALREADY_REGISTERED
        };

        if(!table::contains(validators, parent)) {
            abort ERROR_NEW_PARENT_VALIDATOR_MUST_BE_IN_THE_VALIDATOR_REGISTRY
        };

        let validator = table::borrow_mut(validators, parent);
        let parent_struct = Parent { pub_key_x: pub_key_x, pub_key_y: pub_key_y, self_staked: validator.stake, isActive: true, total_stake: 0, sub_validators: map::new<address, u64>() };
        map::upsert(parents, parent, parent_struct);

        check_active_parents(parents,active_parents, parent);
    }


    fun check_active_parents(parents: &Map<address, Parent>, active_parents: &mut vector<address>, parent: address) {
        let length = vector::length(active_parents);

        if(length < N_VALIDATORS) {
            vector::push_back(active_parents, parent);
            return
        };

        while(length > 0) {
            let parent_addr = vector::borrow(active_parents, length);
            let active_parent = obtain_parent(parents, *parent_addr);
            let self_parent = obtain_parent(parents, parent);
            if(active_parent.total_stake < self_parent.total_stake) {
                vector::remove(active_parents, length);
                vector::push_back(active_parents, parent);
            };
            length = length - 1;
        }
    }


    fun obtain_parent(parents: &Map<address, Parent>, parent: address): Parent {
        if(!map::contains_key(parents, &parent)) {
            abort ERROR_PARENT_DOESNT_EXISTS
        };
        *map::borrow(parents, &parent)
    }

    fun reg_validator_for_parent(active_parents: &mut vector<address>, parents: &mut Map<address, Parent>, validators: &mut Table<address, ValidatorStake>, parentAddr: address, new_parent: address) {
        if(!table::contains(validators, parentAddr)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };

        let validator = table::borrow_mut(validators, parentAddr);
        validator.parent = new_parent;

        let parent = map::borrow_mut(parents, &parentAddr);
        map::upsert(&mut parent.sub_validators, parentAddr, validator.stake);
        if(parent.isActive) {
            parent.total_stake = parent.total_stake + validator.stake + parent.self_staked;
            check_active_parents(parents, active_parents, parentAddr);
        }
    }

    // TODO auto upate function when validator changes his stakes
    // this function needs to change the values in Validators, Parents and also somehow check if the parent is in ActiveParents

    #[view]
    public fun return_all_parents(): Map<address, Parent> acquires Parents {
        let vars = borrow_global<Parents>(@dev);
        vars.map 
    }

    #[view]
    public fun return_all_active_arents(): vector<address> acquires ActiveParents {
        let vars = borrow_global<ActiveParents>(@dev);
        vars.list 
    }

    #[view]
    public fun return_all_active_parents_full(): Map<address, Parent> acquires ActiveParents, Parents {
        let vars = borrow_global<ActiveParents>(@dev);
        let parents = borrow_global<Parents>(@dev);
        let map = map::new<address, Parent>();

        let length = vector::length(&vars.list);
        while(length > 0) {
            let parent_addr = vector::borrow(&vars.list, length-1);
            let parent = return_parent(*parent_addr);
            map::add(&mut map, *parent_addr, parent);
            length = length - 1;
        };
        map 
    }

    #[view]
    public fun return_validator(val: address): ValidatorStake acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!table::contains(&vars.table, val)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };
        return *table::borrow(&vars.table, val)
    }

    #[view]
    public fun return_parent(val: address): Parent acquires Parents {
        let vars = borrow_global<Parents>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_PARENT_DOESNT_EXISTS
        };
        return *map::borrow(&vars.map, &val)
    }

    #[view]
    public fun return_parent_raw(val: address): (String, String, u64, u64, bool, Map<address, u64>) acquires Parents {
        let vars = borrow_global<Parents>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_PARENT_DOESNT_EXISTS
        };
        let parent  = map::borrow(&vars.map, &val);
        return (parent.pub_key_x, parent.pub_key_y, parent.self_staked, parent.total_stake, parent.isActive, parent.sub_validators)
    }

}