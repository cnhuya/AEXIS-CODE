module dev::QiaraTokenVaultsV1{
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

    use dev::QiaraTokensMetadataV1::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV1::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV1::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV1::{Self as TokensTiers};

    use dev::QiaraMarginV1::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV1::{Self as Points, Access as PointsAccess};

    use dev::QiaraSharedV1::{Self as Shared};
    use dev::QiaraChainTypesV1::{Self as ChainTypes};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_VAULT_TYPE: u64 = 2;

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
    struct Vault has key, store, copy, drop{
        total_accumulated_rewards: u256,
        last_update: u64,
    }

    struct GlobalVault has key, copy {
        //  token, chain, provider
        additional_rewards: Map<String,Vault>,
        protocol_reserves: Map<String,Vault>,
        protocol_revenue: Map<String,Vault>
    }


// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { additional_rewards: map::new<String, Vault>(),protocol_reserves: map::new<String, Vault>(),protocol_revenue: map::new<String, Vault>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };
    }

// === ENTRY FUN === //
    fun tttta(number: u64){
        abort(number);
    }

    public fun add_accumulated_rewards(type: String, token: String ,value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev),type, token);

        vault.total_accumulated_rewards = vault.total_accumulated_rewards + value;
        };
    }

    public fun update(type: String, token: String, cap: Permission) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), type, token);
        vault.last_update = timestamp::now_seconds();
    }


// === PUBLIC VIEWS === //

    #[view]
    public fun return_vaults(tokens: vector<String>): GlobalVault acquires GlobalVault {
        return *borrow_global<GlobalVault>(@dev)
    }

// === MUT RETURNS === //
    fun find_vault(vaults: &mut GlobalVault, type: String, token: String): &mut Vault {
        // 1. Identify which map we are targeting
        let target_map = if (type == utf8(b"protocol_revenue")) {
            &mut vaults.protocol_revenue
        } else if (type == utf8(b"protocol_reserves")) {
            &mut vaults.protocol_reserves
        } else if (type == utf8(b"additional_rewards")) {
            &mut vaults.additional_rewards
        } else {
            abort(ERROR_INVALID_VAULT_TYPE)
        };

        // 2. Check the TARGET map (not vaults.map) for the token
        // Note: We provide the type <String, Vault> to help the compiler infer types
        if (!map::contains_key<String, Vault>(target_map, &token)) {
            map::add(target_map, token, Vault {
                last_update: timestamp::now_seconds(),
                total_accumulated_rewards: 0,
            });
        };

        // 3. Return the mutable reference from the chosen map
        map::borrow_mut(target_map, &token)
    }
}
