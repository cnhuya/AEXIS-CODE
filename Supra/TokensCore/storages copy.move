module dev::QiaraTokensStoragesV20{
    use std::signer;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};
    use dev::QiaraTokensRouterV1::{Self as TokensRouter};
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

    struct LockStorage<Chain: store> has key {
        balance: Object<FungibleStore>,
    }

    struct FeeStorage<Chain: store> has key {
        balance: Object<FungibleStore>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer)  {
    }


    public fun init_storages<Token, Chain: store>(admin: &signer) {
        if (!exists<LockStorage<Chain>>(@dev)) {
            let metadata = TokensRouter::get_metadata<Token>();
            let store = primary_fungible_store::ensure_primary_store_exists<Metadata>(signer::address_of(admin), metadata);

            move_to(admin, LockStorage<Chain> { balance: store });
        };
        if (!exists<FeeStorage<Chain>>(@dev)) {
            let metadata = TokensRouter::get_metadata<Token>();
            let store = primary_fungible_store::ensure_primary_store_exists<Metadata>(signer::address_of(admin), metadata);

            move_to(admin, FeeStorage<Chain> { balance: store });
        };
    }
    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------

    inline fun borrow_lock_storage<Chain: store>(): &mut Object<FungibleStore> acquires LockStorage{
        return &mut borrow_global_mut<LockStorage<Chain>>(@dev).balance
    }
    inline fun borrow_fee_storage<Chain: store>(): &mut Object<FungibleStore> acquires FeeStorage{
        return &mut borrow_global_mut<FeeStorage<Chain>>(@dev).balance
    }
}