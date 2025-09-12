module dev::QiaraFunctionsV20 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::signer;
    use std::vector;
    use supra_framework::event;
    use std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_std::from_bcs;
    use std::bcs::{Self as bc};


    struct KeyRegistry has key {
        keys: vector<String>,
    }

    struct Access has key, store, drop { }
    struct FunctionPermission has key, drop { }

    struct FunctionDatabase has key {
        database: Table<String, vector<String>>
    }

    const OWNER: address = @dev;
    const ERROR_CONSTANT_DOES_NOT_EXIST: u64 = 2;
    const ERROR_NOT_ADMIN: u64 = 3;
    const ERROR_HEADER_DOESNT_EXISTS: u64 = 5;
    const ERROR_CONSTANT_ALREADY_EXISTS: u64 = 6;


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer)  {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<FunctionDatabase>(OWNER)) {
            move_to(
                admin,
                FunctionDatabase { database: table::new<String, vector<String>>() }
            );
        };

        if (!exists<KeyRegistry>(OWNER)) {
            move_to(
                admin,
                KeyRegistry {keys: vector::empty<String>() }
            );
        };

    }

    public fun give_access(admin: &signer): Access{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_function_permission(access: &Access): FunctionPermission{
        FunctionPermission {}
    }

    fun register_function(address: &signer, header: String, constant_name: String, permission: &FunctionPermission) acquires FunctionDatabase, KeyRegistry {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<FunctionDatabase>(OWNER);
        let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
        if(!vector::contains(&key_registry.keys, &header)){
            vector::push_back(&mut key_registry.keys, header);
        };
        if (table::contains(&db.database, header)) {
            // Append to the existing vector after checking for uniqueness
            let constants = table::borrow_mut(&mut db.database, header);
            let len = vector::length(constants);
            let i = 0;
            while (i < len) {
                let c_ref = vector::borrow(constants, i);
                if (*c_ref == constant_name) {
                    // Constant with this name already exists for this header
                    abort ERROR_CONSTANT_ALREADY_EXISTS
                };
                i = i + 1;
            };
            vector::push_back(constants, constant_name);
        } else {
            // Create a new vector with the constant
            let vec = vector::empty<String>();
            vector::push_back(&mut vec, constant_name);
            table::add(&mut db.database, header, vec);
        }
    }

    public fun register_function_multi(address: &signer, header: vector<String>, constant_name: vector<String>, permission: &FunctionPermission) acquires KeyRegistry, FunctionDatabase{
        let len = vector::length(&header);
        while(len>0){
            register_function(address, *vector::borrow(&header, len-1), *vector::borrow(&constant_name, len-1), permission);
            len=len-1;
        };
    }

    public fun consume_function(address: &signer, header: String, constant_name: String) acquires FunctionDatabase {
        assert_function_registration(header,constant_name);
        let db = borrow_global_mut<FunctionDatabase>(OWNER);
        let constants = table::borrow_mut(&mut db.database, header);
         let len = vector::length(constants);
        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow_mut(constants, i);
            if (*c_ref == constant_name) {
               let _ =  vector::remove(constants, i);
            };
            i = i + 1;
        };
        abort ERROR_CONSTANT_ALREADY_EXISTS
    }

    #[view]
    public fun viewHeaders(): vector<String> acquires KeyRegistry {
        let key_registry = borrow_global<KeyRegistry>(OWNER);
        key_registry.keys
    }

    #[view]
    public fun viewFunctions(header: String): vector<String> acquires FunctionDatabase {
        let db = borrow_global<FunctionDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_CONSTANT_DOES_NOT_EXIST;
        };

        let constants_ref = table::borrow(&db.database, header);
        *constants_ref // return a copy of the vector
    }


        #[view]
        public fun assert_function_registration(header: String,constant_name: String): bool acquires FunctionDatabase {
            let db = borrow_global<FunctionDatabase>(OWNER);

            if (!table::contains(&db.database, header)) {
                return false; // header not found  capability can't exist
            };

            let constants_ref: &vector<String> = table::borrow(&db.database, header);
            let len = vector::length(constants_ref);

            let i = 0;
            while (i < len) {
                let c_ref = vector::borrow(constants_ref, i);
                if (*c_ref == constant_name) {
                    return true;
                };
                i = i + 1;
            };

            // If not found
            false
        }

}
