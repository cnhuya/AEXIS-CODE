module dev::QiaraLiquidityV2{
    use std::signer;
    use std::timestamp;
    use std::vector;    
    use std::string::{Self as String, String, utf8};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils ::{Self as string_utils};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::dispatchable_fungible_asset;
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};
    use supra_framework::account;

    use dev::QiaraTokensMetadataV12::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV12::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV12::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV12::{Self as TokensTiers};

    use dev::QiaraMarginV16::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV16::{Self as Points, Access as PointsAccess};

    use dev::QiaraSharedV6::{Self as Shared};
    use dev::QiaraChainTypesV11::{Self as ChainTypes};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 2;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }


    struct Permissions has key, store, drop {
        margin: MarginAccess,
        points: PointsAccess,
        tokens_rates: TokensRatesAccess,
        tokens_core: TokensCoreAccess,
    }


// === STRUCTS === //
   // Maybe in the future remove this, and move total borrowed into global vault? idk tho how would it do because of the phantom type tag
    struct Vault has key, store, copy, drop{
        total_accumulated_rewards: u256,
        last_update: u64,
    }

    struct GlobalVault has key {
        //  token, chain, provider
        map: Map<String,Vault>
    }


// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { map: map::new<String, Vault>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };
    }

// === ENTRY FUN === //
    fun tttta(number: u64){
        abort(number);
    }

    public fun add_accumulated_rewards(token: String ,value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token);
            vault.total_accumulated_rewards = vault.total_accumulated_rewards + value;
            internal_update(vault);
        };
    }

    fun internal_update(vault: &mut Vault){
        vault.last_update = timestamp::now_seconds();
    }


// === PUBLIC VIEWS === //

    #[view]
    public fun return_vaults(tokens: vector<String>): Map<String, Vault> acquires GlobalVault {
        let vaults = borrow_global<GlobalVault>(@dev);
        return vaults.map
    }

// === MUT RETURNS === //
    fun find_vault(vaults: &mut GlobalVault, token: String): &mut Vault {
        let metadata = TokensCore::get_metadata(token);
        if(!map::contains_key(&vaults.map, &token)){
            map::add(&mut vaults.map, token, Vault {
                last_update: timestamp::now_seconds(),
                total_accumulated_rewards: 0,
            });
        };
        return map::borrow_mut(&mut vaults.map, &token)

    }
}
