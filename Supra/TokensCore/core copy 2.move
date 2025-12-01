module dev::QiaraTokensCoreV18 {
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
    use dev::QiaraTokensTypesV18::{Self as TokensType,  Bitcoin, Ethereum, Solana, Sui, Deepbook, Injective, Aerodrome, Virtuals, Supra, USDT, USDC};
    use dev::QiaraTokensMetadataV18::{Self as TokensMetadata};
    use dev::QiaraTokensOmnichainV18::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraChainTypesV18::{Self as ChainTypes};

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
        tokens_omnichain_access: TokensOmnichainAccess,
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
    fun tttta(id: u64){
        abort(id);
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer){

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { tokens_omnichain_access: TokensOmnichain::give_access(admin)});
        };
    }

    public entry fun inits(admin: &signer){
        init_token(admin, utf8(b"Qiara7 Ethereum"), utf8(b"QETH"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/ethereum.webp"), 1_438_269_983, 1, 120_698_129, 120_698_129, 120_698_129, 1);
        init_token(admin, utf8(b"Qiara7 Bitcoin"), utf8(b"QBTC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/bitcoin.webp"), 1_231_006_505, 0, 21_000_000, 19_941_253, 19_941_253, 1);
        init_token(admin, utf8(b"Qiara7 Solana"), utf8(b"QSOL"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/solana.webp"), 1_584_316_800, 10, 614_655_961, 559_139_255, 614_655_961, 1);
        init_token(admin, utf8(b"Qiara7 Sui"), utf8(b"QSUI"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/sui.webp"), 1_683_062_400, 90, 10_000_000_000, 3_680_742_933, 10_000_000_000, 1);
        init_token(admin, utf8(b"Qiara7 Deepbook"), utf8(b"QDEEP"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/deepbook.webp"),  1_683_072_000, 491, 10_000_000_000, 4_368_147_611, 10_000_000_000, 1);
        init_token(admin, utf8(b"Qiara7 Injective"), utf8(b"QINJ"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/injective.webp"), 1_636_416_000, 121, 100_000_000, 100_000_000, 100_000_000, 1);
        init_token(admin, utf8(b"Qiara7 Virtuals"), utf8(b"QVIRTUALS"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/virtuals.webp"), 1_614_556_800, 524, 1_000_000_000, 656_082_020, 1_000_000_000, 1);
        init_token(admin, utf8(b"Qiara7 Supra"), utf8(b"QSUPRA"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/supra.webp"), 1_732_598_400, 500, 100_000_000_000, 21_000_700_000, 80_600_180_397, 1);
        init_token(admin, utf8(b"Qiara7 USDT"), utf8(b"QUSDT"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdt.webp"), 0, 47, 185_977_352_465, 185_977_352_465, 185_977_352_465, 255);
        init_token(admin, utf8(b"Qiara7 USDC"), utf8(b"QUSDC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdc.webp"), 0, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 255);   
    }


    public entry fun init_depo(signer: &signer) acquires ManagedFungibleAsset, Permissions{
        ma_drilla_lul(signer, utf8(b"Qiara7 Ethereum"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Ethereum"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Bitcoin"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Solana"), utf8(b"Solana"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Sui"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Deepbook"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Injective"), utf8(b"Injective"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Virtuals"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Qiara7 Supra"), utf8(b"Supra"));
        ma_drilla_lul(signer, utf8(b"Qiara7 USDT"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Qiara7 USDC"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Qiara7 USDC"), utf8(b"Sui"));
    }

    fun ma_drilla_lul(signer:&signer, token: String, chain: String) acquires ManagedFungibleAsset, Permissions{
        ChainTypes::ensure_valid_chain_name(&chain);
        let fa = mint(token, chain, INIT_SUPPLY, give_permission(&give_access(signer)));
        let asset = get_metadata(token);
      //  tttta(1);
        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),asset);
         //      tttta(57);
        let managed = authorized_borrow_refs(asset);
       // tttta(97);
        deposit(store, fa, chain, &managed.transfer_ref);
    }


    fun init_token(admin: &signer, name: String, symbol: String, icon: String, creation: u64,oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8 ){
        let constructor_ref = &object::create_named_object(admin, bcs::to_bytes(&name));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name,
            symbol, 
            6, 
            icon,
            utf8(b"https://x.com/QiaraProtocol"),
        );
        fungible_asset::set_untransferable(constructor_ref);
        let asset = get_metadata(name);
        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);

        let metadata_object_signer = object::generate_signer(constructor_ref);

      //  let init_fa = fungible_asset::mint(&mint_ref, INIT_SUPPLY);


        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&name));
       // tttta(20);
        assert!(fungible_asset::is_untransferable(asset),1);
        let sign_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(admin),asset);

        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the FA coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV10"),
            string::utf8(b"deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV10"),
            string::utf8(b"withdraw"),
        );
   
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );
   
        move_to(&metadata_object_signer,ManagedFungibleAsset { transfer_ref, burn_ref, mint_ref }); // <:!:initialize
      //  TokensMetadata::create_metadata(admin, name, creation, oracleID, max_supply, circulating_supply, total_supply, stable);

    }
    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------

    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun deposit<T: key>(store: Object<T>,fa: FungibleAsset, chain: String, transfer_ref: &TransferRef) acquires Permissions{
        ChainTypes::ensure_valid_chain_name(&chain);
        let x = bcs::to_bytes(&object::owner(store));
       // tttta(14);
        let y = fungible_asset::symbol(fungible_asset::store_metadata(store));
      //       tttta(1);
        TokensOmnichain::change_UserTokenSupply(y, chain, x, fungible_asset::amount(&fa), true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }

    /// Withdraw function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun withdraw<T: key>(store: Object<T>,amount: u64, chain: String, transfer_ref: &TransferRef): FungibleAsset acquires Permissions {
        ChainTypes::ensure_valid_chain_name(&chain);
        let x = bcs::to_bytes(&object::owner(store));
       // tttta(14);
        let y = fungible_asset::symbol(fungible_asset::store_metadata(store));
      //  tttta(0);
        TokensOmnichain::change_UserTokenSupply(y, chain, x, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
       // assert!(!fungible_asset::is_untransferable(store),2);
     //   assert!(fungible_asset::is_untransferable(store),1);
       //        tttta(100);
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount)
    }

    /// Burn fungible assets directly from the caller's own account.
    /// Anyone can call this to burn their own tokens.
    public entry fun burn(signer: &signer, token: String, chain: String, amount: u64) acquires Permissions, ManagedFungibleAsset {
        let wallet = primary_fungible_store::primary_store(signer::address_of(signer), get_metadata(token));
        let asset = get_metadata(token);
        let managed = authorized_borrow_refs(asset);
        let fa = withdraw(wallet, amount, chain,&managed.transfer_ref);
        TokensOmnichain::change_TokenSupply(fungible_asset::symbol(get_metadata_from_address(object::object_address(&fungible_asset::metadata_from_asset(&fa)))), chain, fungible_asset::amount(&fa), false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        fungible_asset::burn(&managed.burn_ref, fa);
    }

    // Only allowed modules are allowed to call mint function, 
    // in this scenario we allow only the module bridge_handler to be able to call this function.
    public fun mint(token: String, chain: String, amount: u64, cap: Permission): FungibleAsset acquires ManagedFungibleAsset,Permissions {
        let asset = get_metadata(token);
        let managed = authorized_borrow_refs(asset);
        let fa = fungible_asset::mint(&managed.mint_ref, amount);
        TokensOmnichain::change_TokenSupply(fungible_asset::symbol(get_metadata_from_address(object::object_address(&fungible_asset::metadata_from_asset(&fa)))), chain,amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        return fa
    }

    // Test function trying to bypass custom flow
    public entry fun bypass_transfer(sender:&signer, to: address, token: String, chain: String, amount: u64) {
        ChainTypes::ensure_valid_chain_name(&chain);
        let asset = get_metadata(token);

        let from = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
        let to = primary_fungible_store::ensure_primary_store_exists(to,asset);
        
        dispatchable_fungible_asset::transfer(sender, from, to, amount)
    }

    public entry fun transfer(sender:&signer, to: address, token: String, chain: String, amount: u64) {
        ChainTypes::ensure_valid_chain_name(&chain);
        let asset = get_metadata(token);

        let from = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
        let to = primary_fungible_store::ensure_primary_store_exists(to,asset);
        
        dispatchable_fungible_asset::transfer(sender, from, to, amount)
    }

    public entry fun transfer_internal(sender:&signer, to: address, token: String, chain: String, amount: u64) acquires ManagedFungibleAsset,Permissions {
        ChainTypes::ensure_valid_chain_name(&chain);
        let asset = get_metadata(token);

      //  assert!(object::is_untransferable(asset),1474); aborted
      //  assert!(fungible_asset::is_untransferable(asset),1);
      //  assert!(!fungible_asset::is_untransferable(asset),2);
        let from = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
        let to = primary_fungible_store::ensure_primary_store_exists(to,asset);
        //assert!(object::is_untransferable(from),1);
        //assert!(object::is_untransferable(to),0);

        let managed = authorized_borrow_refs(asset);
      //  tttta(147);
        let fa = withdraw(from, amount, chain, &managed.transfer_ref);
        //        tttta(999);
        deposit(to, fa, chain, &managed.transfer_ref);
    }

    // Function to pre-"burn" tokens when bridging out, but the transaction isnt yet validated so the tokens arent really burned yet.
    // Later implement function to claim locked tokens if the bridge tx fails
 /*   public fun lock<Chain>(user: &signer, fa: FungibleAsset, lock: &mut BridgeLock<Chain>, perm: Permission){
        deposit(&mut lock.balance, fa, &managed.transfer_ref);
    }

    public fun unlock<Chain>(user: &signer, amount: u64, lock: &mut BridgeLock<Chain>, perm: Permission): FungibleAsset{
        return withdraw<FungibleStore, Chain>(&mut lock.balance, amount)
    }

   public entry fun redeem(signer: &signer, token:String, chain:String) acquires ManagedFungibleAsset, Permissions {
        let asset = get_metadata(token);
        
        let amount = (TokensOmnichain::return_balance(token, chain,bcs::to_bytes(&signer::address_of(signer))) as u64);
        let fa = mint(amount, give_permission(&give_access(signer)));
     //   TokensOmnichain::p_burn(token, chain,bcs::to_bytes(&signer::address_of(signer)), amount, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
      
        let wallet = primary_fungible_store::primary_store(signer::address_of(signer), asset);
        deposit(wallet, fa, chain, &managed.transfer_ref);
    }
    */



    // --------------------------
    // HELPERS
    // --------------------------

    /// Borrow the immutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(asset: Object<Metadata>): &ManagedFungibleAsset acquires ManagedFungibleAsset {borrow_global<ManagedFungibleAsset>(object::object_address(&asset))}


    // --------------------------
    // VIEWS
    // --------------------------
    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(token:String): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&token));
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata_from_address(address:address): Object<Metadata> {
        object::address_to_object<Metadata>(address) // here
    }

    #[view]
    public fun get_coin_metadata(token:String): CoinMetadata {
        let metadata = get_metadata(token);
        CoinMetadata{
            address: object::create_object_address(&ADMIN,bcs::to_bytes(&token)),
            name: fungible_asset::name(metadata),
            symbol: fungible_asset::symbol(metadata),
            decimals: fungible_asset::decimals(metadata),
            decimals_scale: DECIMALS_N,
            icon_uri: fungible_asset::icon_uri(metadata),
            project_uri: fungible_asset::project_uri(metadata),
        }
    }
}