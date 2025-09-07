module dev::QiaraStorageV18 {
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
    struct StorageChangePermission has key, drop { }

    struct ConstantDatabase has key {
        database: Table<String, vector<Constant>>
    }

    struct Constant has store, drop, copy {
        name: String,
        value: Any,
        editable: bool
    }

    struct U8 has store, key { } 
    struct U16 has store, key { } 
    struct U32 has store, key { } 
    struct U64 has store, key { } 
    struct U128 has store, key { } 
    struct U256 has store, key { } 
    struct Address has store, key { } 
    struct Bool has store, key { } 

    struct Any has drop, store, copy { type: String, data: vector<u8> }

    #[event]
    struct ConstantChange has drop, store {
        address: address,
        old_constant: Constant,
        new_constant: Constant
    }

    const OWNER: address = @dev;
    const ERROR_CONSTANT_DOES_NOT_EXIST: u64 = 2;
    const ERROR_NOT_ADMIN: u64 = 3;
    const ERROR_CONSTANT_CANT_BE_EDITED: u64 = 4;
    const ERROR_HEADER_DOESNT_EXISTS: u64 = 5;
    const ERROR_CONSTANT_ALREADY_EXISTS: u64 = 6;
    const ERROR_INVALID_VALUE_TYPE: u64 = 7;

    fun make_constant(name: String, value: Any, editable: bool): Constant {
        Constant { name, value, editable }
    }

    fun make_any<T>(value: vector<u8>): Any {
        Any { type: type_info::type_name<T>(), data: value }
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) acquires KeyRegistry, ConstantDatabase{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<ConstantDatabase>(OWNER)) {
            move_to(
                admin,
                ConstantDatabase { database: table::new<String, vector<Constant>>() }
            );
        };

        if (!exists<KeyRegistry>(OWNER)) {
            move_to(
                admin,
                KeyRegistry {keys: vector::empty<String>() }
            );
        };
        // 6 DECIMALS
        // 1% = 1_000_000
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"INFLATION"), 17_500_000, true, &give_change_permission(&give_access(admin))); // 17,50%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT"), 100_000, false, &give_change_permission(&give_access(admin))); // 0.1% a month
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_FEE"), 500, false, &give_change_permission(&give_access(admin))); // 0,0005%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_INCREASE"), 100, false, &give_change_permission(&give_access(admin))); // 0,0001% a month
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"TREASURY_FEE"), 1_000, false, &give_change_permission(&give_access(admin))); // 0,001% a month
        register_constant<bool>(admin, utf8(b"QiaraToken"), utf8(b"TRANSFERABLE"), false, true, &give_change_permission(&give_access(admin)));
        register_constant<address>(admin, utf8(b"QiaraToken"), utf8(b"TREASURY_RECEIPENT"), @0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd, true, &give_change_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"), 100_000_000, true, &give_change_permission(&give_access(admin))); // 100
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"BURN_TAX"), 1_000_000, true, &give_change_permission(&give_access(admin))); // 1
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"), 1_000_000, true, &give_change_permission(&give_access(admin))); // 1%
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"), 500, true, &give_change_permission(&give_access(admin))); // 50.0%
    }

    public fun give_access(admin: &signer): Access{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_change_permission(access: &Access): StorageChangePermission{
        StorageChangePermission {}
    }

    fun register_constant<T: drop>(address: &signer, header: String, constant_name: String, value: T, editable: bool, permission: &StorageChangePermission) acquires ConstantDatabase, KeyRegistry {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<ConstantDatabase>(OWNER);
        let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
        let any = make_any<T>(bc::to_bytes(&value));
        let new_constant = make_constant(constant_name, any, editable);
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
                if (c_ref.name == constant_name) {
                    // Constant with this name already exists for this header
                    abort ERROR_CONSTANT_ALREADY_EXISTS
                };
                i = i + 1;
            };
            vector::push_back(constants, new_constant);
        } else {
            // Create a new vector with the constant
            let vec = vector::empty<Constant>();
            vector::push_back(&mut vec, new_constant);
            table::add(&mut db.database, header, vec);
        }
    }

    public fun handle_registration(address: &signer, header: String, constant_name: String, value: vector<u8>, value_type: String, editable: bool, permission: &StorageChangePermission) acquires KeyRegistry, ConstantDatabase{
        if(value_type == utf8(b"u8")){
             register_constant<u8>(address, header, constant_name, from_bcs::to_u8(value), editable, permission);
        } else if  (value_type == utf8(b"u16")){
             register_constant<u16>(address, header, constant_name, from_bcs::to_u16(value), editable, permission);
        } else if  (value_type == utf8(b"u32")){
             register_constant<u32>(address, header, constant_name, from_bcs::to_u32(value), editable, permission);
        } else if  (value_type == utf8(b"u64")){
             register_constant<u64>(address, header, constant_name, from_bcs::to_u64(value), editable, permission);
        } else if  (value_type == utf8(b"u128")){
             register_constant<u128>(address, header, constant_name, from_bcs::to_u128(value), editable, permission);
        } else if  (value_type == utf8(b"u256")){
             register_constant<u256>(address, header, constant_name, from_bcs::to_u256(value), editable, permission);
        } else if  (value_type == utf8(b"bool")){
             register_constant<bool>(address, header, constant_name, from_bcs::to_bool(value), editable, permission);
        } else if  (value_type == utf8(b"address")){
             register_constant<address>(address, header, constant_name, from_bcs::to_address(value), editable, permission);
        } else{
            abort ERROR_INVALID_VALUE_TYPE
        }
    }

    fun get_constant(db: &mut ConstantDatabase, header: String, name: String): &mut Constant{

        if (!table::contains(&db.database, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants = table::borrow_mut(&mut db.database, header);

        let i = vector::length(constants);
        while (i > 0) {
            i = i - 1;
            let constant = vector::borrow_mut(constants, i); // copy or move depending on definition
            if (constant.name == name) {
                return constant;
            };
        };
        abort ERROR_HEADER_DOESNT_EXISTS
    }

    public fun change_constant(address: &signer,header: String,name: String,new_value: vector<u8>, permission: &StorageChangePermission) acquires ConstantDatabase {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_CONSTANT_DOES_NOT_EXIST;
        };

        let constant = get_constant(db, header, name);

        if (!constant.editable) {
            abort ERROR_CONSTANT_CANT_BE_EDITED
        };

        let old_constant = make_constant(
            constant.name,
            constant.value,
            constant.editable
        );

        // Update the constant
        constant.value.data = new_value;

        let new_constant = make_constant(
            constant.name,
            constant.value,
            constant.editable
        );

        event::emit(ConstantChange {
            address: signer::address_of(address),
            old_constant,
            new_constant
        });
    }


    #[view]
    public fun viewHeaders(): vector<String> acquires KeyRegistry {
        let key_registry = borrow_global<KeyRegistry>(OWNER);
        key_registry.keys
    }

    #[view]
    public fun viewConstants(header: String): vector<Constant> acquires ConstantDatabase {
        let db = borrow_global<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_CONSTANT_DOES_NOT_EXIST;
        };

        let constants_ref = table::borrow(&db.database, header);
        *constants_ref // return a copy of the vector
    }

    #[view]
    public fun viewConstant_raw(header: String, constant_name: String): Constant acquires ConstantDatabase {
        let db = borrow_global<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants_ref: &vector<Constant> = table::borrow(&db.database, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                // clone the Constant to return
                return make_constant(c_ref.name, c_ref.value, c_ref.editable);
            };
            i = i + 1;
        };

        // If not found
        abort ERROR_CONSTANT_DOES_NOT_EXIST
    }

    #[view]
    public fun viewConstant(header: String, constant_name: String): vector<u8> acquires ConstantDatabase {
        let db = borrow_global<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants_ref: &vector<Constant> = table::borrow(&db.database, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                return c_ref.value.data
            };
            i = i + 1;
        };

        // If not found
        abort ERROR_CONSTANT_DOES_NOT_EXIST
    }
     #[view]
    public fun expect_u8(data: vector<u8>): u8 {
        from_bcs::to_u8(data)
    }
     #[view]
    public fun expect_u16(data: vector<u8>): u16 {
        from_bcs::to_u16(data)
    }
     #[view]
    public fun expect_u32(data: vector<u8>): u32 {
        from_bcs::to_u32(data)
    }
     #[view]
    public fun expect_u64(data: vector<u8>): u64 {
        from_bcs::to_u64(data)
    }
     #[view]
    public fun expect_u128(data: vector<u8>): u128 {
        from_bcs::to_u128(data)
    }
     #[view]
    public fun expect_u256(data: vector<u8>): u256 {
        from_bcs::to_u256(data)
    }
     #[view]
    public fun expect_bool(data: vector<u8>): bool {
        from_bcs::to_bool(data)
    }
    
     #[view]
    public fun expect_address(data: vector<u8>): address {
        from_bcs::to_address(data)
    }
 #[view]
    public fun expect_bytes(data: vector<u8>): vector<u8> {
        from_bcs::to_bytes(data)
    }
 #[view]
    public fun expect_string(data: vector<u8>): string::String {
        from_bcs::to_string(data)
    }


}
