module dev::QiaraTokensCoreV27 {
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
    use supra_framework::account;
    use supra_framework::object::{Self, Object};
    use supra_framework::event;
    use std::string::{Self as string, String, utf8};

    use dev::QiaraMathV9::{Self as Math};
    use dev::QiaraTokensMetadataV27::{Self as TokensMetadata};
    use dev::QiaraTokensOmnichainV27::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraTokensStoragesV27::{Self as TokensStorage, Access as TokensStorageAccess};
    use dev::QiaraTokensTiersV27::{Self as TokensTiers};

    use dev::QiaraChainTypesV19::{Self as ChainTypes};
    use dev::QiaraTokenTypesV19::{Self as TokensType};

    const ADMIN: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_BLACKLISTED: u64 = 2;
    const ERROR_ACCOUNT_DOES_NOT_EXISTS: u64 = 3;
    const ERROR_SUFFICIENT_BALANCE: u64 = 4;

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

// === EVENTS === //
    #[event]
    struct RequestBridgeEvent has copy, drop, store {
        address: vector<u8>,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct BridgedEvent has copy, drop, store {
        address: vector<u8>,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct BridgeRefundEvent has copy, drop, store {
        address: vector<u8>,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct FinalizeBridgeEvent has copy, drop, store {
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

// === INIT === //
    fun init_module(admin: &signer){

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { tokens_omnichain_access: TokensOmnichain::give_access(admin)});
        };
    }

// === ENTRY FUNCTIONS === //
    public entry fun inits(admin: &signer){
        init_token(admin, utf8(b"Ethereum"), utf8(b"QETH"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/ethereum.webp"), 1_438_269_983, 1, 120_698_129, 120_698_129, 120_698_129, 1);
        init_token(admin, utf8(b"Bitcoin"), utf8(b"QBTC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/bitcoin.webp"), 1_231_006_505, 0, 21_000_000, 19_941_253, 19_941_253, 1);
        init_token(admin, utf8(b"Solana"), utf8(b"QSOL"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/solana.webp"), 1_584_316_800, 10, 614_655_961, 559_139_255, 614_655_961, 1);
        init_token(admin, utf8(b"Sui"), utf8(b"QSUI"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/sui.webp"), 1_683_062_400, 90, 10_000_000_000, 3_680_742_933, 10_000_000_000, 1);
        init_token(admin, utf8(b"Deepbook"), utf8(b"QDEEP"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/deepbook.webp"),  1_683_072_000, 491, 10_000_000_000, 4_368_147_611, 10_000_000_000, 1);
        init_token(admin, utf8(b"Injective"), utf8(b"QINJ"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/injective.webp"), 1_636_416_000, 121, 100_000_000, 100_000_000, 100_000_000, 1);
        init_token(admin, utf8(b"Virtuals"), utf8(b"QVIRTUALS"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/virtuals.webp"), 1_614_556_800, 524, 1_000_000_000, 656_082_020, 1_000_000_000, 1);
        init_token(admin, utf8(b"Supra"), utf8(b"QSUPRA"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/supra.webp"), 1_732_598_400, 500, 100_000_000_000, 21_000_700_000, 80_600_180_397, 1);
        init_token(admin, utf8(b"USDT"), utf8(b"QUSDT"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdt.webp"), 0, 47, 185_977_352_465, 185_977_352_465, 185_977_352_465, 255);
        init_token(admin, utf8(b"USDC"), utf8(b"QUSDC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdc.webp"), 0, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 255);   
    }


    public entry fun init_depo(signer: &signer) acquires ManagedFungibleAsset, Permissions{
        ma_drilla_lul(signer, utf8(b"Ethereum"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Ethereum"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Bitcoin"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Solana"), utf8(b"Solana"));
        ma_drilla_lul(signer, utf8(b"Sui"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Deepbook"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Injective"), utf8(b"Injective"));
        ma_drilla_lul(signer, utf8(b"Virtuals"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Supra"), utf8(b"Supra"));
        ma_drilla_lul(signer, utf8(b"USDT"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"USDC"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"USDC"), utf8(b"Sui"));
    }

    fun ma_drilla_lul(signer:&signer, token: String, chain: String) acquires ManagedFungibleAsset, Permissions{
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);


        let fa = mint(token, chain, INIT_SUPPLY, give_permission(&give_access(signer)));
        let asset = get_metadata(token);
        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),asset);
        let managed = authorized_borrow_refs(asset);
        deposit(store, fa, chain, &managed.transfer_ref);
    }


    fun init_token(admin: &signer, name: String, symbol: String, icon: String, creation: u64,oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8 ){
        name = TokensType::ensure_valid_token(&name);
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



        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&name));
        assert!(fungible_asset::is_untransferable(asset),1);
        let sign_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(admin),asset);

        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the FA coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV23"),
            string::utf8(b"c_deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV23"),
            string::utf8(b"c_withdraw"),
        );
   
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );
   
        move_to(&metadata_object_signer,ManagedFungibleAsset { transfer_ref, burn_ref, mint_ref }); // <:!:initialize
        TokensMetadata::create_metadata(admin, symbol, creation, oracleID, max_supply, circulating_supply, total_supply, stable);

    }
// === OVERWRITE FUNCTIONS === //

    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    /// 
    public fun deposit<T: key>(store: Object<T>,fa: FungibleAsset, chain: String, transfer_ref: &TransferRef) acquires Permissions{
        ChainTypes::ensure_valid_chain_name(&chain);
        fungible_asset::set_frozen_flag(transfer_ref, store, true);
        TokensOmnichain::change_UserTokenSupply(fungible_asset::symbol(fungible_asset::store_metadata(store)), chain, bcs::to_bytes(&object::owner(store)), fungible_asset::amount(&fa), true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }
    /// Withdraw function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun withdraw<T: key>(store: Object<T>,amount: u64, chain: String, transfer_ref: &TransferRef): FungibleAsset acquires Permissions {
        ChainTypes::ensure_valid_chain_name(&chain);
        fungible_asset::set_frozen_flag(transfer_ref, store, true);
        TokensOmnichain::change_UserTokenSupply(fungible_asset::symbol(fungible_asset::store_metadata(store)), chain, bcs::to_bytes(&object::owner(store)), amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount)
    }
 
 
   public fun c_deposit<T: key>(store: Object<T>,fa: FungibleAsset, transfer_ref: &TransferRef) {
        fungible_asset::set_frozen_flag(transfer_ref, store, true);
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }
    /// Withdraw function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun c_withdraw<T: key>(store: Object<T>,amount: u64, transfer_ref: &TransferRef): FungibleAsset {
        fungible_asset::set_frozen_flag(transfer_ref, store, true);
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount)
    }

// === TOKENOMICS FUNCTIONS === //
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


    public fun p_transfer(validator: &signer, sender:vector<u8>, to: vector<u8>, token: String, chain: String, amount: u64, perm: Permission) acquires Permissions {
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);
        TokensOmnichain::change_UserTokenSupply(token, chain, sender, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        TokensOmnichain::change_UserTokenSupply(token, chain, to, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 

    }

    public entry fun transfer(sender:&signer, to: address, token: String, chain: String, amount: u64) acquires ManagedFungibleAsset,Permissions {
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);
        TokensOmnichain::ensure_token_supports_chain(token, chain);
        let asset = get_metadata(token);

        if(!account::exists_at(to)){
            burn(sender, token, chain, amount);
            TokensOmnichain::change_UserTokenSupply(token, chain, bcs::to_bytes(&to), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            return
        };

        let from = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
        let to = primary_fungible_store::ensure_primary_store_exists(to,asset);

        let managed = authorized_borrow_refs(asset);
        let fa = withdraw(from, amount, chain, &managed.transfer_ref);
        deposit(to, fa, chain, &managed.transfer_ref);
    }

// === BRIDGE FUNCTIONS === //
    // Function to pre-"burn" tokens when bridging out, but the transaction isnt yet validated so the tokens arent really burned yet.
    // Later implement function to claim locked tokens if the bridge tx fails
    public fun p_request_bridge(validator: &signer, user: vector<u8>, token: String, chain: String, amount: u64, perm: Permission) acquires Permissions{
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);

        let legit_amount = (TokensOmnichain::return_adress_balance(token, chain, user) as u64);
        assert!(legit_amount >= amount, ERROR_SUFFICIENT_BALANCE);

        TokensOmnichain::change_UserTokenSupply(token, chain, user, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 

        event::emit(RequestBridgeEvent {
            address: user,
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });

    }

    public fun request_bridge(user: &signer, token: String, chain: String, amount: u64) acquires Permissions, ManagedFungibleAsset{
        let asset = get_metadata(token);
        let wallet = primary_fungible_store::primary_store(signer::address_of(user), get_metadata(token));
        let managed = authorized_borrow_refs(asset);
        let fa = withdraw(wallet, amount, chain,&managed.transfer_ref);

        let legit_amount = (TokensOmnichain::return_adress_balance(token, chain,bcs::to_bytes(&signer::address_of(user))) as u64);
        assert!(legit_amount >= amount, ERROR_SUFFICIENT_BALANCE);

        deposit(TokensStorage::return_lock_storage(token, chain), fa, chain, &managed.transfer_ref);
    
        event::emit(RequestBridgeEvent {
            address: bcs::to_bytes(&signer::address_of(user)),
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
    
    }

    public fun bridged(validator: &signer, user: address, token: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);

        if(!account::exists_at(user)){
            TokensOmnichain::change_UserTokenSupply(token, chain, bcs::to_bytes(&user), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            TokensOmnichain::change_TokenSupply(token, chain,amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
            
            event::emit(BridgedEvent {
                address: bcs::to_bytes(&user),
                token: token,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });
            return
        };
     
        let asset = get_metadata(token);
        let fa = mint(token, chain, amount, give_permission(&give_access(validator)));

        let store = primary_fungible_store::ensure_primary_store_exists(user,asset);
        let managed = authorized_borrow_refs(asset);
        deposit(store, fa, chain, &managed.transfer_ref);
    
        event::emit(BridgedEvent {
            address: bcs::to_bytes(&user),
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
    
    }

    public fun finalize_bridge(validator: &signer,  token: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        let asset = get_metadata(token);
        let managed = authorized_borrow_refs(asset);
        let fa = withdraw(TokensStorage::return_lock_storage(token, chain), amount, chain, &managed.transfer_ref);

        TokensOmnichain::change_TokenSupply(fungible_asset::symbol(get_metadata_from_address(object::object_address(&fungible_asset::metadata_from_asset(&fa)))), chain, fungible_asset::amount(&fa), false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        fungible_asset::burn(&managed.burn_ref, fa);
    
        event::emit(FinalizeBridgeEvent {
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
    
    }

    public fun finalize_failed_bridge(validator: &signer, user: address, token: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);

        if(!account::exists_at(user)){
            TokensOmnichain::change_UserTokenSupply(token, chain, bcs::to_bytes(&user), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            TokensOmnichain::change_TokenSupply(token, chain,amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
            
            event::emit(BridgeRefundEvent {
                address: bcs::to_bytes(&user),
                token: token,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });
            return
        };
     
        let asset = get_metadata(token);
        let fa = mint(token, chain, amount, give_permission(&give_access(validator)));

        let store = primary_fungible_store::ensure_primary_store_exists(user,asset);
        let managed = authorized_borrow_refs(asset);
        deposit(store, fa, chain, &managed.transfer_ref);
    
        event::emit(BridgeRefundEvent {
            address: bcs::to_bytes(&user),
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
    
    
    }

    // Function that can be only called by Validator, used to redeem tokens to existing Supra wallet.
   public fun redeem(validator: &signer, permissioneless_wallet: vector<u8>, supra_wallet: address, token:String, chain:String, perm: Permission) acquires ManagedFungibleAsset, Permissions {
        let asset = get_metadata(token);
        ChainTypes::ensure_valid_chain_name(&chain);
        token = TokensType::ensure_valid_token(&token);       
        assert!(account::exists_at(supra_wallet), ERROR_ACCOUNT_DOES_NOT_EXISTS);

        let amount = (TokensOmnichain::return_adress_balance(token, chain,bcs::to_bytes(&signer::address_of(validator))) as u64);
        let fa = mint(token, chain, amount, give_permission(&give_access(validator)));
        TokensOmnichain::change_UserTokenSupply(token, chain, permissioneless_wallet, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
      
        let managed = authorized_borrow_refs(asset);
        let wallet = primary_fungible_store::primary_store(supra_wallet, asset);
        deposit(wallet, fa, chain, &managed.transfer_ref);
    }
    
    // gets value by usd


    #[view]
    public fun ensure_fees(validator: address, symbol: String, chain: String, amount: u64): u64{
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(symbol);
        let tier = TokensMetadata::get_coin_metadata_tier(&metadata);
        let flat_fee = TokensTiers::flat_usd_fee(tier); // 0.0005$
        let transfer_fee = TokensTiers::transfer_fee(tier); // 0.00025%

        let token_value = TokensMetadata::getValue(symbol, (flat_fee as u256));
        return ((transfer_fee as u64) * amount) + (token_value as u64)

    //    let fa = mint(token, chain, amount, give_permission(&give_access(validator)));

    //    let wallet = primary_fungible_store::primary_store(signer::address_of(validator), asset);
   //     deposit(wallet, fa, chain, ref);
    }


// === HELPFER FUNCTIONS === //

    /// Borrow the immutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(asset: Object<Metadata>): &ManagedFungibleAsset acquires ManagedFungibleAsset {borrow_global<ManagedFungibleAsset>(object::object_address(&asset))}




// === VIEW FUNCTIONS === //
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