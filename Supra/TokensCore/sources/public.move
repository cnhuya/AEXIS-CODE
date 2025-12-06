module dev::QiaraTokensPublicV34{
    use std::signer;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};

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



    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer)  {
    }



    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------


}