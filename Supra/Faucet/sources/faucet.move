module dev::QiaraFaucetV1{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use aptos_std::from_bcs;
    use std::string::{Self as string, String, utf8};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraEventV15::{Self as Event};
    use dev::QiaraSharedV6::{Self as Shared};
    use dev::QiaraStorageV1::{Self as storage, Access as StorageAccess};
    use dev::QiaraTokenTypesV11::{Self as TokensTypes};
    use dev::QiaraTokensCoreV12::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
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
    struct Permissions has key, store, drop {
        tokens_core: TokensCore::Access,
    }

    struct Users has key{
        table: Table<String, u64>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Users>(@dev)) {
            move_to(admin, Users { table: table::new<String, u64>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_omnichain: TokensOmnichain::give_access(admin), tokens_core: TokensCore::give_access(admin),tokens_metadata: TokensMetadata::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin), auto:  auto::give_access(admin)});
        };
    }

// NATIVE INTERFACE
    public entry fun faucet(signer: &signer, user: vector<u8>, name: String) acquires Users {
        Shared::assert_is_sub_owner(shared, sender);
        let users_table = borrow_global_mut<Users>(@dev);

        if(!table::contains(&users_table.table, &user)) {
            table::add(&mut users_table.table, &name, timestamp::now_seconds());
        };

        let time_period = storage::expect_u64(storage::viewConstant(utf8(b"QiaraFaucet"), utf8(b"TIME_PERIOD"))),
        let faucet_usd_value = storage::expect_u64(storage::viewConstant(utf8(b"QiaraFaucet"), utf8(b"USD_VALUE"))),

        let tokens = TokensTypes::return_full_nick_names_list();
        let len_tokens = vector::length(&tokens);
        let i = 0;

        while (i < len_tokens) {
            let token = *vector::borrow(&tokens, i);
            let metadata = TokensTypes::get_coin_metadata_by_symbol(token);
            let price = (TokensTypes::get_coin_metadata_price(&metadata) as u256);
            let denom = (TokensTypes::get_coin_metadata_denom(&metadata) as u256);

            let tokens = oracle::convert_to_token(token, faucet_usd_value);
            TokensCore::mint_to(user, name, token, metadata.chain, tokens, TokensCoreAccess::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
    }



}