module dev::QiaraTokensSharedV42{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;

// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;
    const ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS:u64 = 1;
    const ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE:u64 = 2;
    const ERROR_IS_ALREADY_SUB_OWNER: u64 = 3;

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

    //owner -> allowed sub-owners
    struct SharedStorage has key{
        storage: Table<vector<u8>, vector<vector<u8>>>
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<SharedStorage>(@dev)) {
            move_to(admin, SharedStorage { storage: table::new<vector<u8>, vector<vector<u8>>>() });
        };
    }

// NATIVE INTERFACE
    public entry fun create_shared_storage(signer: &signer) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, bcs::to_bytes(&signer::address_of(signer)))) {
            table::add(&mut shared.storage,   bcs::to_bytes(&signer::address_of(signer)), vector::empty<vector<u8>>());
        };
    }

    public entry fun allow_sub_owner(signer: &signer, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, bcs::to_bytes(&signer::address_of(signer)))) {
            table::add(&mut shared.storage,  bcs::to_bytes(&signer::address_of(signer)), vector::empty<vector<u8>>());
        };

        let sub_owners = table::borrow_mut(&mut shared.storage, bcs::to_bytes(&signer::address_of(signer)));
        vector::push_back(sub_owners, sub_owner);
    }

    public entry fun remove_sub_owner(signer: &signer, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        assert!(table::contains(&shared.storage, bcs::to_bytes(&signer::address_of(signer))),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        let sub_owners = table::borrow_mut(&mut shared.storage, bcs::to_bytes(&signer::address_of(signer)));
        assert!(vector::contains(sub_owners, &bcs::to_bytes(&signer::address_of(signer))), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);
        vector::remove_value(sub_owners, &sub_owner);
    }

// PERMISSIONELESS INTERFACE
    public entry fun p_create_shared_storage(validator: &signer, owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            table::add(&mut shared.storage, owner, vector::empty<vector<u8>>());
        };
    }

    public entry fun p_allow_sub_owner(validator: &signer, owner: vector<u8>, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, owner)) {
            table::add(&mut shared.storage, owner, vector::empty<vector<u8>>());
        };

        let sub_owners = table::borrow_mut(&mut shared.storage, owner);
        assert!(vector::contains(sub_owners, &owner), ERROR_IS_ALREADY_SUB_OWNER);
        vector::push_back(sub_owners, sub_owner);
    }

    public entry fun p_remove_sub_owner(validator: &signer, owner: vector<u8>, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        assert!(table::contains(&shared.storage,owner),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        let sub_owners = table::borrow_mut(&mut shared.storage, owner);
        assert!(vector::contains(sub_owners, &owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);
        vector::remove_value(sub_owners, &sub_owner);
    }

    #[view]
    public fun return_sub_owners(owner: vector<u8>): vector<vector<u8>> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage,owner),ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS );
        *table::borrow_mut(&mut shared.storage, owner)
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