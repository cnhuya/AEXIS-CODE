module dev::QiaraCapabilitiesV15 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::signer;
    use std::vector;
    use supra_framework::event;
    use std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_std::from_bcs;
    use std::bcs::{Self as bc};


    struct Access has key, store, drop { }
    struct CapabilitiesChangePermission has key, drop { }

    struct Capability has store, drop, key, copy {
        name: String,
        removable: bool,
    }

    struct KeyRegistry has key {
        keys: vector<String>,
    }

    struct Capabilities has store, key{
        table: Table<String, vector<Capability>>
    }

    #[event]
    struct CapabilityCreated has drop, store {
        address: address,
        capability: Capability,
    }

    const OWNER: address = @dev;
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_HEADER_DOESNT_EXISTS: u64 = 2;
    const ERROR_CAPABILITY_ALREADY_EXISTS: u64 = 3;
    const ERROR_CAPABILITY_DOESNT_EXISTS: u64 = 4;

    fun make_capability(name: String, removable: bool): Capability {
        Capability { name, removable}
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) acquires Capabilities, KeyRegistry{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<KeyRegistry>(OWNER)) {
            move_to(admin,KeyRegistry {keys: vector::empty<String>() });
        };
        if (!exists<Capabilities>(OWNER)) {
            move_to(admin, Capabilities { table: table::new<String, vector<Capability>>()});
        };
        
        create_capability(admin, signer::address_of(admin), utf8(b"QiaraToken"), utf8(b"TOKEN_CLAIM_CAPABILITY"), true, give_change_permission(&give_access(admin))); // 50.0%

    }

    public fun give_access(admin: &signer): Access{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_change_permission(access: &Access): CapabilitiesChangePermission{
        CapabilitiesChangePermission {}
    }

    public fun create_capability(address: &signer, addr: address, header: String, name: String, removable: bool, cap: CapabilitiesChangePermission) acquires Capabilities, KeyRegistry {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<Capabilities>(addr);
        let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
        let new_cap = make_capability(name, removable);
        if(!vector::contains(&key_registry.keys, &header)){
            vector::push_back(&mut key_registry.keys, header);
        };
        if (table::contains(&db.table, header)) {
            let constants = table::borrow_mut(&mut db.table, header);
            let len = vector::length(constants);
            let i = 0;
            while (i < len) {
                let c_ref = vector::borrow(constants, i);
                if (c_ref.name == name) {
                    abort ERROR_CAPABILITY_ALREADY_EXISTS
                };
                i = i + 1;
            };
            vector::push_back(constants, new_cap);
        } else {
            // Create a new vector with the constant
            let vec = vector::empty<Capability>();
            vector::push_back(&mut vec, new_cap);
            table::add(&mut db.table, header, vec);
        }
    }

    public fun remove_capability(address: &signer, addr: address, header: String, name: String, cap: CapabilitiesChangePermission) acquires Capabilities, KeyRegistry {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<Capabilities>(addr);
        let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
        if(!vector::contains(&key_registry.keys, &header)){
            abort ERROR_HEADER_DOESNT_EXISTS
        };
        if (table::contains(&db.table, header)) {
            let constants = table::borrow_mut(&mut db.table, header);
            let len = vector::length(constants);
            let i = 0;
            while (i < len) {
                let c_ref = vector::borrow(constants, i);
                if (c_ref.name == name && c_ref.removable == true) {
                    vector::remove(constants, i);
                };
                i = i + 1;
            };
        } else {
            abort ERROR_CAPABILITY_DOESNT_EXISTS
        }
    }


    #[view]
    public fun viewHeaders(): vector<String> acquires KeyRegistry {
        let key_registry = borrow_global<KeyRegistry>(OWNER);
        key_registry.keys
    }

    #[view]
    public fun viewCapabilities(address: address, header: String): vector<Capability> acquires Capabilities {
        let db = borrow_global<Capabilities>(address);

        if (!table::contains(&db.table, header)) {
            abort ERROR_CAPABILITY_DOESNT_EXISTS;
        };

        let constants_ref = table::borrow(&db.table, header);
        *constants_ref // return a copy of the vector
    }

    #[view]
    public fun viewCapability(address: address, header: String, constant_name: String): Capability acquires Capabilities {
        let db = borrow_global<Capabilities>(address);

        if (!table::contains(&db.table, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants_ref: &vector<Capability> = table::borrow(&db.table, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                // clone the Constant to return
                return make_capability(c_ref.name, c_ref.removable);
            };
            i = i + 1;
        };

        // If not found
        abort ERROR_CAPABILITY_DOESNT_EXISTS
    }
}
