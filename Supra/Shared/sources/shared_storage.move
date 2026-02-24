module dev::QiaraSharedV2{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use aptos_std::from_bcs;
    use std::string::{Self as string, String, utf8};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraEventV2::{Self as Event};
// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;
    const ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS:u64 = 1;
    const ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE:u64 = 2;
    const ERROR_IS_ALREADY_SUB_OWNER: u64 = 3;
    const ERROR_SUB_OWNER_DOESNT_EXISTS_IN_ANY_SHARED_STORAGE: u64 = 4;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS: u64 = 5;
    const ERROR_ADDRESS_DOESNT_MATCH_SIGNER: u64 = 6;
    const ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE: u64 = 7;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS: u64 = 8;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}


    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
    
// === STRUCTS === //
    struct Permissions has key {
    }

    struct Ownership has key, store, copy, drop{
        owner: vector<u8>,
        sub_owners: vector<vector<u8>>,
    }

    //STORAGE: owner -> allowed sub-owners
    //STORAGE_REGISTRY: sub_owner -> shared storages registry, in which he is allowed as sub-owner
    struct SharedStorage has key{
        storage: Table<vector<u8>, Map<String, Ownership>>,
        storage_registry: Table<vector<u8>, Map<vector<u8>, vector<String>>> // change it to vector<vector>u8>> bcs names is kinda useeles, cant really view it eaasily...
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<SharedStorage>(@dev)) {
            move_to(admin, SharedStorage { storage: table::new<vector<u8>, Map<String, Ownership>>(), storage_registry: table::new<vector<u8>, Map<vector<u8>, vector<String>>>() });
        };
    }

// NATIVE INTERFACE
    public entry fun create_shared_storage(signer: &signer, name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let addr_bytes = bcs::to_bytes(&signer::address_of(signer));

        if (!table::contains(&shared.storage, addr_bytes)) {
            table::add(&mut shared.storage, addr_bytes, map::new<String, Ownership>());
        };

        let user_map = table::borrow_mut(&mut shared.storage, addr_bytes);

        if (!map::contains_key(user_map, &name)) {
            map::upsert(user_map, name, Ownership { owner: bcs::to_bytes(&signer::address_of(signer)), sub_owners: vector::empty<vector<u8>>() });
        } else {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
        ];
        Event::emit_shared_storage_event(utf8(b"Storage Created"), data);

    }

    public entry fun allow_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let owner = bcs::to_bytes(&signer::address_of(signer));

        if (!table::contains(&shared.storage, owner)) {
            table::add(&mut shared.storage, owner, map::new<String, Ownership>());
        };

        let user_map = table::borrow_mut(&mut shared.storage, owner);

        if (!map::contains_key(user_map, &name)) {
            map::add(user_map, name, Ownership { owner: bcs::to_bytes(&signer::address_of(signer)), sub_owners: vector::empty<vector<u8>>() });
        };

        let ownership_record = map::borrow_mut(user_map, &name);
        assert!(ownership_record.owner == bcs::to_bytes(&signer::address_of(signer)), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        vector::push_back(&mut ownership_record.sub_owners, sub_owner);

        // sub_owners
        if (!table::contains(&shared.storage_registry, sub_owner)) {
            table::add(&mut shared.storage_registry, sub_owner, map::new<vector<u8>, vector<String>>());
        };

        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);

        if (!map::contains_key(sub_owners_registry, &owner)) {
            map::add(sub_owners_registry, owner, vector::empty<String>());
        };
        let vect = map::borrow_mut(sub_owners_registry, &owner);
        vector::push_back(vect, name);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Added"), data);
    }

    public entry fun remove_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let map = table::borrow_mut(&mut shared.storage, bcs::to_bytes(&signer::address_of(signer)));

        let ownership_record = map::borrow_mut(map, &name);

        assert!(ownership_record.owner == bcs::to_bytes(&signer::address_of(signer)), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        assert!(vector::contains(&ownership_record.sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);

        vector::remove_value(&mut ownership_record.sub_owners, &sub_owner);
        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        let vect = map::borrow_mut(sub_owners_registry, &bcs::to_bytes(&signer::address_of(signer)));
        vector::remove_value(vect, &name);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Removed"), data);
    }

// PERMISSIONELESS INTERFACE
    public entry fun p_create_shared_storage(validator: &signer, name: String, owner:vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            table::add(&mut shared.storage, owner, map::new<String, Ownership>());
        };

        let user_map = table::borrow_mut(&mut shared.storage, owner);

        if (!map::contains_key(user_map, &name)) {
            map::upsert(user_map, name, Ownership { owner: owner, sub_owners: vector::empty<vector<u8>>() });
        } else {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&owner)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
        ];
        Event::emit_shared_storage_event(utf8(b"Storage Created"), data);
    }

    public entry fun p_allow_sub_owner(validator: &signer,  name: String, owner: vector<u8>, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            table::add(&mut shared.storage, owner, map::new<String, Ownership>());
        };

        let map = table::borrow_mut(&mut shared.storage, owner);

        let ownership_record = map::borrow_mut(map, &name);
        
        vector::push_back(&mut ownership_record.sub_owners, sub_owner);
        assert!(vector::contains(&ownership_record.sub_owners, &owner), ERROR_IS_ALREADY_SUB_OWNER);

        // sub_owners
        if (!table::contains(&shared.storage_registry, sub_owner)) {
            table::add(&mut shared.storage_registry, sub_owner, map::new<vector<u8>, vector<String>>());
        };

        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);

        if (!map::contains_key(sub_owners_registry, &owner)) {
            map::add(sub_owners_registry, owner, vector::empty<String>());
        };
        let vect = map::borrow_mut(sub_owners_registry, &owner);
        vector::push_back(vect, name);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&owner)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Added"), data);
    }

    public entry fun p_remove_sub_owner(validator: &signer, name: String, owner: vector<u8>, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let map = table::borrow_mut(&mut shared.storage, owner);
        let ownership_record = map::borrow_mut(map, &name);
        assert!(vector::contains(&ownership_record.sub_owners, &owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);
        vector::remove_value(&mut ownership_record.sub_owners, &sub_owner);
        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        let vect = map::borrow_mut(sub_owners_registry, &owner);
        vector::remove_value(vect, &name);
    
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&owner)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Removed"), data);
    }

    #[view]
    public fun return_shared_storages(owner: vector<u8>): Map<String, Ownership> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        *table::borrow_mut(&mut shared.storage, owner)
    }

    #[view]
    public fun return_sub_owners_registry(sub_owner: vector<u8>): Map<vector<u8>, vector<String>> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage_registry,sub_owner),ERROR_SUB_OWNER_DOESNT_EXISTS_IN_ANY_SHARED_STORAGE );
        *table::borrow_mut(&mut shared.storage_registry, sub_owner)
    }

    #[view]
    public fun assert_shared_storage(name: String): bool acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        return true
    }

    public fun assert_is_sub_owner(owner: vector<u8>, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            abort ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS
        };

        let user_map = table::borrow(&shared.storage, owner);

        if (!map::contains_key(user_map, &name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = map::borrow(user_map, &name);

        assert!(vector::contains(&ownership_record.sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);
    }

    public fun assert_is_owner(owner: vector<u8>, name: String) acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            abort ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS
        };

        let user_map = table::borrow(&shared.storage, owner);

        if (!map::contains_key(user_map, &name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = map::borrow(user_map, &name);

        assert!(ownership_record.owner == owner, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
    }

}