module dev::QiaraNonceV1{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;

// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;

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

    struct Nonces has key, store{
        table: Table<vector<u8>, u256>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Nonces>(@dev)) {
            move_to(admin, Nonces {table: table::new<vector<u8>, u256>()});
        };
    }

    public fun increment_nonce( user: vector<u8>) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
            table::add(&mut nonces.table, user, 1);
        } else {
            let nonce_ref = table::borrow_mut(&mut nonces.table, user);
            let current_nonce = *nonce_ref;
            *nonce_ref = current_nonce + 1;
        }
    }

    #[view]
    public fun return_user_nonce(user: vector<u8>): u256 acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
           return 0
        };
        return *table::borrow(&nonces.table, user)
    }
 }
