module dev::QiaraTokensCoreV5 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::dispatchable_fungible_asset;
    use supra_framework::primary_fungible_store;
    use supra_framework::function_info;
    use supra_framework::object::{Self, Object};
    use std::string::{Self as string, String, utf8};

    use dev::QiaraMathV9::{Self as Math};
    use dev::QiaraTokensTypesV5::{Self as TokensType,  Bitcoin, Ethereum, Solana, Sui, Deepbook, Injective, Aerodrome, Virtuals, Supra, USDT, USDC};
    use dev::QiaraTokensMetadataV5::{Self as TokensMetadata};
    use dev::QiaraTokensBridgeStorageV5::{Self as TokensBridgeStorage, Access as TokensBridgeStorageAccess};
    use dev::QiaraChainTypesV16::{Self as ChainTypes, Sui as SuiChain, Base, Solana as SolanaChain, Injective as InjectiveChain, Supra as SupraChain };

    const ADMIN: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_BLACKLISTED: u64 = 2;

    const INIT_SUPPLY: u64 = 1_000_000_000_000;
    const DECIMALS_N: u64 = 1_000_000;    

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
        tokens_bridge_storage_access: TokensBridgeStorageAccess,
    }

    struct ManagedFungibleAsset has key {
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        mint_ref: MintRef,
    }

    struct CoinMetadata has key, store{
        address: address,
        name: String,
        symbol: String, 
        decimals: u8,
        decimals_scale: u64,
        icon_uri: String,
        project_uri: String,
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer)  {

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { tokens_bridge_storage_access: TokensBridgeStorage::give_access(admin)});
        };

        init_token<Bitcoin>(admin, utf8(b"Qiara Bitcoin"), utf8(b"QBTC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/bitcoin.webp"), 1_231_006_505, 0, 21_000_000, 19_941_253, 19_941_253, 1);
        init_token<Ethereum>(admin, utf8(b"Qiara Ethereum"), utf8(b"QETH"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/ethereum.webp"), 1_438_269_983, 1, 120_698_129, 120_698_129, 120_698_129, 1);
        init_token<Solana>(admin, utf8(b"Qiara SUI"), utf8(b"QSOL"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/solana.webp"), 1_584_316_800, 10, 614_655_961, 559_139_255, 614_655_961, 1);
        init_token<Sui>(admin, utf8(b"Qiara USDC"), utf8(b"QSUI"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/sui.webp"), 1_683_062_400, 90, 10_000_000_000, 3_680_742_933, 10_000_000_000, 1);
        init_token<Deepbook>(admin, utf8(b"Qiara USDT"), utf8(b"QDEEP"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/deepbook.webp"),  1_683_072_000, 491, 10_000_000_000, 4_368_147_611, 10_000_000_000, 1);
        init_token<Injective>(admin, utf8(b"Qiara USDT"), utf8(b"QINJ"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/injective.webp"), 1_636_416_000, 121, 100_000_000, 100_000_000, 100_000_000, 1);
        init_token<Virtuals>(admin, utf8(b"Qiara USDT"), utf8(b"QVIRTUALS"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/virtuals.webp"), 1_614_556_800, 524, 1_000_000_000, 656_082_020, 1_000_000_000, 1);
        init_token<Supra>(admin, utf8(b"Qiara USDT"), utf8(b"QSUPRA"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/supra.webp"), 1_732_598_400, 500, 100_000_000_000, 21_000_700_000, 80_600_180_397, 1);
        init_token<USDT>(admin, utf8(b"Qiara USDT"), utf8(b"QUSDT"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/usdt.webp"), 0, 47, 185_977_352_465, 185_977_352_465, 185_977_352_465, 255);
        init_token<USDC>(admin, utf8(b"Qiara USDT"), utf8(b"QUSDC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/coins/usdc.webp"), 0, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 255);   

        for_testing(admin);

    }

    fun for_testing(signer: &signer) acquires ManagedFungibleAsset{

        ma_drilla_lul<Bitcoin, SuiChain>(signer);
        ma_drilla_lul<Ethereum, Base>(signer);
        ma_drilla_lul<Solana, SolanaChain>(signer);
        ma_drilla_lul<Sui, SuiChain>(signer);
        ma_drilla_lul<Deepbook, SuiChain>(signer);
        ma_drilla_lul<Injective, InjectiveChain>(signer);
        ma_drilla_lul<Virtuals, Base>(signer);
        ma_drilla_lul<Supra, SupraChain>(signer);
        ma_drilla_lul<USDC, Base>(signer);
        ma_drilla_lul<USDC, SuiChain>(signer);
        ma_drilla_lul<USDT, Base>(signer);
        ma_drilla_lul<USDT, SuiChain>(signer);

    }

    fun ma_drilla_lul<Token: key, Chain>(signer: &signer) acquires ManagedFungibleAsset{
        let asset = get_metadata<Token>();
        let wallet = primary_fungible_store::primary_store(signer::address_of(signer), asset);
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));

        deposit<FungibleStore, Token, Chain>(wallet, mint<Token, Chain>(47474747474747, give_permission(&give_access(signer))), &managed.transfer_ref);

    }

    fun init_token<Token>(admin: &signer, name: String, symbol: String, icon: String, creation: u64,oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8 ){
        let constructor_ref = &object::create_named_object(admin, bcs::to_bytes(&type_info::type_name<Token>()));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name,
            symbol, 
            6, 
            icon,
            utf8(b"https://x.com/QiaraProtocol"),
        );
        let asset = get_metadata<Token>();
        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);

        let metadata_object_signer = object::generate_signer(constructor_ref);

        let init_fa = fungible_asset::mint(&mint_ref, INIT_SUPPLY);


        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&type_info::type_name<Token>()));


        let sign_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(admin),asset);

        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the FA coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV5"),
            string::utf8(b"deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV5"),
            string::utf8(b"withdraw"),
        );
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );

        move_to(&metadata_object_signer,ManagedFungibleAsset { transfer_ref, burn_ref, mint_ref }); // <:!:initialize
        fungible_asset::set_untransferable(&constructor_ref);
        TokensMetadata::create_metadata<Token>(admin, creation, oracleID, max_supply, circulating_supply, total_supply, stable);
        TokensBridgeStorage::init_lock<Token>(admin);
    }
    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------

    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun deposit<FungibleStore: key, Chain>(store: Object<FungibleStore>,fa: FungibleAsset) acquires ManagedFungibleAsset {
        TokensBridgeStorage::change_UserTokenSupply<Chain>(bcs::to_bytes(&object::object_address(&store)), fungible_asset::amount(&fa), true, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access)); 
        let managed = borrow_global<ManagedFungibleAsset>(@dev);
        fungible_asset::deposit_with_ref(store, fa, &managed.transfer_ref);
    }

    /// Withdraw function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun withdraw<FungibleStore: key, Chain>(store: Object<FungibleStore>,amount: u64): FungibleAsset acquires ManagedFungibleAsset {
        TokensBridgeStorage::change_UserTokenSupply<Chain>(bcs::to_bytes(&object::object_address(&store)), amount, false, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access)); 
        let managed = borrow_global<ManagedFungibleAsset>(@dev);
        fungible_asset::withdraw_with_ref(store, amount, &managed.transfer_ref)
    }

    /// Burn fungible assets directly from the caller's own account.
    /// Anyone can call this to burn their own tokens.
    public entry fun burn<Token, Chain>(signer: &signer, amount: u64) acquires ManagedFungibleAsset, Permissions {
        let asset = get_metadata<Token>();
        let wallet = primary_fungible_store::primary_store(signer::address_of(signer), asset);
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let fa = fungible_asset::withdraw_with_ref(&managed.transfer_ref, wallet, amount);
        TokensBridgeStorage::p_burn<Token, Chain>(bcs::to_bytes(&signer::address_of(signer)), amount,TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
        fungible_asset::burn(&managed.burn_ref, fa);
    }

    // Only allowed modules are allowed to call mint function, 
    // in this scenario we allow only the module bridge_handler to be able to call this function.
    public fun mint<Token, Chain>(amount: u64, cap: Permission): FungibleAsset acquires ManagedFungibleAsset, Permissions {
        let asset = get_metadata<Token>();
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        TokensBridgeStorage::change_TokenSupply<Token, Chain>(amount, true, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
        fungible_asset::mint(&managed.mint_ref, amount)
    }

    public entry fun redeem<Token: key, Chain>(signer: &signer) acquires ManagedFungibleAsset, Permissions {
        let asset = get_metadata<Token>();
        
        let amount = (TokensBridgeStorage::return_balance<Token, Chain>(bcs::to_bytes(&signer::address_of(signer))) as u64);
        let fa = mint<Token, Chain>(amount, give_permission(&give_access(signer)));
        TokensBridgeStorage::p_burn<Token, Chain>(bcs::to_bytes(&signer::address_of(signer)), amount, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
      
        let wallet = primary_fungible_store::primary_store(signer::address_of(signer), asset);
        deposit<FungibleStore, Token, Chain>(wallet, fa);
    }



    // --------------------------
    // HELPERS
    // --------------------------

    /// Borrow the immutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(owner: &signer,asset: Object<Metadata>,): &ManagedFungibleAsset acquires ManagedFungibleAsset {assert!(object::is_owner(asset, signer::address_of(owner)), ERROR_NOT_ADMIN);borrow_global<ManagedFungibleAsset>(object::object_address(&asset))}


    // --------------------------
    // VIEWS
    // --------------------------
    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata<Token>(): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&type_info::type_name<Token>()));
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    public fun get_coin_metadata<Token>(): CoinMetadata {
        let metadata = get_metadata<Token>();
        CoinMetadata{
            address: object::create_object_address(&ADMIN,bcs::to_bytes(&type_info::type_name<Token>())),
            name: fungible_asset::name(metadata),
            symbol: fungible_asset::symbol(metadata),
            decimals: fungible_asset::decimals(metadata),
            decimals_scale: DECIMALS_N,
            icon_uri: fungible_asset::icon_uri(metadata),
            project_uri: fungible_asset::project_uri(metadata),
        }
    }
}