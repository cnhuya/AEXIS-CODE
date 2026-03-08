module dev::QiaraFaucetV1{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::from_bcs;
    use std::string::{Self as string, String, utf8};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraEventV15::{Self as Event};
    use dev::QiaraSharedV6::{Self as Shared};
    use dev::QiaraStorageV1::{Self as storage, Access as StorageAccess};

    use dev::QiaraChainTypesV11::{Self as ChainTypes};
    use dev::QiaraTokenTypesV11::{Self as TokensTypes};

    use dev::QiaraTokensCoreV12::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraOracleV1::{Self as Oracle, Access as OracleAccess};
// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;
    const ERROR_ALREADY_CLAIMED_FREE_TOKENS_PLEASE_WAIT:u64 = 1;
    const ERORR_UNAUTHORIZED:u64 = 2;

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
            move_to(admin, Permissions {tokens_core: TokensCore::give_access(admin)});
        };
    }

    fun ensure_safety(token: String, chain: String){
        ChainTypes::ensure_valid_chain_name(chain);
        TokensTypes::ensure_token_supported_for_chain(TokensTypes::convert_token_nickName_to_name(token), chain)
    }

    fun internal_faucet(signer:&signer, shared: String, token: String, chain: String) acquires Permissions{
        ensure_safety(token, chain);

        let usd_value_raw = storage::expect_u64(storage::viewConstant(utf8(b"QiaraFaucet"), utf8(b"USD_VALUE")));
        let usd_value_u256 = (usd_value_raw as u256);

        let amount = Oracle::convert_to_token(token, usd_value_u256);

        TokensCore::mint_to(signer::address_of(signer), shared, token, chain, (amount as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
    }

    public entry fun faucet(signer: &signer, user: vector<u8>, shared: String) acquires Users, Permissions {
        assert!(bcs::to_bytes(&signer::address_of(signer)) == user, ERORR_UNAUTHORIZED);
        Shared::assert_is_sub_owner(shared, user);

        let users_table = borrow_global_mut<Users>(@dev);

        if(!table::contains(&users_table.table, shared)) {
            table::add(&mut users_table.table, shared, timestamp::now_seconds());
        };

        let time_period = storage::expect_u64(storage::viewConstant(utf8(b"QiaraFaucet"), utf8(b"TIME_PERIOD")));

        let user_last_claim = table::borrow_mut(&mut users_table.table, shared);

        if(timestamp::now_seconds() - *user_last_claim < time_period) {
            abort(ERROR_ALREADY_CLAIMED_FREE_TOKENS_PLEASE_WAIT);
        };

        internal_faucet(signer, shared, utf8(b"Ethereum"), utf8(b"Base"));
        internal_faucet(signer, shared, utf8(b"Ethereum"), utf8(b"Sui"));
        internal_faucet(signer, shared, utf8(b"Ethereum"), utf8(b"Monad"));
        internal_faucet(signer, shared, utf8(b"Ethereum"), utf8(b"Ethereum"));
    
        internal_faucet(signer, shared, utf8(b"USDC"), utf8(b"Ethereum"));
        internal_faucet(signer, shared, utf8(b"USDT"), utf8(b"Ethereum"));
        internal_faucet(signer, shared, utf8(b"Virtuals"), utf8(b"Ethereum"));

        internal_faucet(signer, shared, utf8(b"Sui"), utf8(b"Sui"));
        internal_faucet(signer, shared, utf8(b"Deepbook"), utf8(b"Sui"));
        internal_faucet(signer, shared, utf8(b"Monad"), utf8(b"Monad"));
        internal_faucet(signer, shared, utf8(b"USDC"), utf8(b"Monad"));
        internal_faucet(signer, shared, utf8(b"USDT0"), utf8(b"Monad"));
        internal_faucet(signer, shared, utf8(b"AUSD"), utf8(b"Monad"));
        internal_faucet(signer, shared, utf8(b"earnAUSD"), utf8(b"Monad"));

        internal_faucet(signer, shared, utf8(b"Bitcoin"), utf8(b"Monad"));
        internal_faucet(signer, shared, utf8(b"Bitcoin"), utf8(b"Ethereum"));
        internal_faucet(signer, shared, utf8(b"Bitcoin"), utf8(b"Sui"));

        internal_faucet(signer, shared, utf8(b"Virtuals"), utf8(b"Base"));
        internal_faucet(signer, shared, utf8(b"Supra"), utf8(b"Supra"));
        internal_faucet(signer, shared, utf8(b"USDT"), utf8(b"Base"));
        internal_faucet(signer, shared, utf8(b"USDC"), utf8(b"Base"));
        internal_faucet(signer, shared, utf8(b"Qiara"), utf8(b"Sui"));
        internal_faucet(signer, shared, utf8(b"Qiara"), utf8(b"Supra"));

        table::upsert(&mut users_table.table, shared, timestamp::now_seconds());
    }

}