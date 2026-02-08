module dev::QiaraTokensSharedV47{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use aptos_std::from_bcs;

// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;
    const ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS:u64 = 1;
    const ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE:u64 = 2;
    const ERROR_IS_ALREADY_SUB_OWNER: u64 = 3;
    const ERROR_SUB_OWNER_DOESNT_EXISTS_IN_ANY_SHARED_STORAGE: u64 = 4;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS: u64 = 5;

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

    struct Ownership has key, store{
        owner: vector<u8>,
        sub_owners: vector<vector<u8>>,
    }

    //STORAGE: owner -> allowed sub-owners
    //STORAGE_REGISTRY: sub_owner -> shared storages registry, in which he is allowed as sub-owner
    struct SharedStorage has key{
        storage: Table<String, Ownership>,
        storage_registry: Table<vector<u8>, String>
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<SharedStorage>(@dev)) {
            move_to(admin, SharedStorage { storage: table::new<vector<u8>, Ownership>(), storage_registry: table::new<vector<u8>, Ownership>() });
        };
    }

// NATIVE INTERFACE
    public entry fun create_shared_storage(signer: &signer, name: String) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage,  name, Ownership { owner: bcs::to_bytes(&signer::address_of(signer)), sub_owners: vector::empty<vector<u8>>() });
        } else {
            assert!(false,  ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS);
        }
    }

    public entry fun allow_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage,  name, Ownership { owner: bcs::to_bytes(&signer::address_of(signer)), sub_owners: vector::empty<vector<u8>>() });
        };
        if (!table::contains(&shared.storage_registry, sub_owner)) {
            table::add(&mut shared.storage_registry, sub_owner, vector::empty<String>());
        };

        let sub_owners = table::borrow_mut(&mut shared.storage, name);
        vector::push_back(sub_owners, sub_owner);
        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::push_back(sub_owners_registry, name);
    }

    public entry fun remove_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        assert!(table::contains(&shared.storage, name),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        let sub_owners = table::borrow_mut(&mut shared.storage, name);
        assert!(vector::contains(sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);
        vector::remove_value(sub_owners, &sub_owner);
        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::remove_value(sub_owners_registry, &name);
    }

// PERMISSIONELESS INTERFACE
    public entry fun p_create_shared_storage(validator: &signer, name: String, owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage,  name, Ownership { owner: owner, sub_owners: vector::empty<vector<u8>>() });
        };

    }

    public entry fun p_allow_sub_owner(validator: &signer, owner: vector<u8>, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            table::add(&mut shared.storage, owner, vector::empty<vector<u8>>());
        };
        if (!table::contains(&shared.storage_registry, owner)) {
            table::add(&mut shared.storage_registry, owner, vector::empty<vector<u8>>());
        };

        let sub_owners = table::borrow_mut(&mut shared.storage, owner);
        assert!(vector::contains(sub_owners, &owner), ERROR_IS_ALREADY_SUB_OWNER);
        vector::push_back(sub_owners, sub_owner);
        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::push_back(sub_owners_registry, owner);
    }

    public entry fun p_remove_sub_owner(validator: &signer, owner: vector<u8>, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        assert!(table::contains(&shared.storage,owner),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        let sub_owners = table::borrow_mut(&mut shared.storage, owner);
        assert!(vector::contains(sub_owners, &owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);
        vector::remove_value(sub_owners, &sub_owner);
        let sub_owners_registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::remove_value(sub_owners_registry, &owner);
    }

    #[view]
    public fun return_sub_owners(owner: vector<u8>): vector<vector<u8>> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage,owner),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        *table::borrow_mut(&mut shared.storage, owner)
    }

    #[view]
    public fun return_sub_owners_registry(sub_owner: vector<u8>): vector<vector<u8>> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage_registry,sub_owner),ERROR_SUB_OWNER_DOESNT_EXISTS_IN_ANY_SHARED_STORAGE );
        *table::borrow_mut(&mut shared.storage_registry, sub_owner)
    }

    //deprecated
    #[view]
    public fun assert_has_shared_storage(address: address): bool acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage,bcs::to_bytes(&address)),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        return true
    }

    #[view]
    public fun assert_shared_storage(owner: vector<u8>): bool acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage,owner),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        return true
    }


//0x307864346663646261343133666631303365656339393661303762373935383437613862346365356333323864333564393834336463356563323233306465363035

//0x20d4fcdba413ff103eec996a07b795847a8b4ce5c328d35d9843dc5ec2230de605
    #[view]
    public fun abcreturn(owner: vector<u8>): vector<u8>{
        return bcs::to_bytes(&owner)
    }

    #[view]
    public fun abcreturna(addr: address): vector<u8>{
        return bcs::to_bytes(&addr)
    }

    #[view]
    public fun abcreturnaa(addr: vector<u8>): vector<u8>{
        return from_bcs::to_bytes(addr)
    }

    #[view]
    public fun abcreturnaaa(addr: vector<u8>): address{
        return from_bcs::to_address(addr)
    }

    #[view]
    public fun assert_is_sub_owner(owner: vector<u8>, sub_owner: vector<u8>): bool acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage,owner),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        let sub_owners = table::borrow_mut(&mut shared.storage, owner);
        if(vector::contains(sub_owners, &sub_owner)){
            return true
        } else {
            return false
        }
    }

}