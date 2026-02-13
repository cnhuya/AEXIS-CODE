module dev::QiaraTokensCoreV2 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::from_bcs;
    use std::type_info::{Self, TypeInfo};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::dispatchable_fungible_asset;
    use supra_framework::primary_fungible_store;
    use supra_framework::function_info;
    use supra_framework::account;
    use supra_framework::object::{Self, Object};
    use std::string::{Self as string, String, utf8};

    use dev::QiaraMathV1::{Self as Math};
    use dev::QiaraTokensMetadataV2::{Self as TokensMetadata};
    use dev::QiaraTokensOmnichainV2::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraTokensTiersV2::{Self as TokensTiers};
    use dev::QiaraTokensQiaraV2::{Self as TokensQiara,  Access as TokensQiaraAccess};

    use dev::QiaraNonceV1::{Self as Nonce, Access as NonceAccess};

    use dev::QiaraEventV5::{Self as Event};
    use dev::QiaraStoragesV2::{Self as Storages};

    use dev::QiaraChainTypesV2::{Self as ChainTypes};
    use dev::QiaraTokenTypesV2::{Self as TokensType};
    use dev::QiaraProviderTypesV2::{Self as ProviderTypes};

    const ADMIN: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_BLACKLISTED: u64 = 2;
    const ERROR_ACCOUNT_DOES_NOT_EXISTS: u64 = 3;
    const ERROR_SUFFICIENT_BALANCE: u64 = 4;

    //100_000_000

    //1_000_000 = 1%
    //100 = 0.0001%

    //18_446_744_073_709_551_615
    //1_000_000_000_000_000_000_000_000
    //1_000_000_000_000_000_000
    const INIT_SUPPLY: u64 = 1_000_000_000_000; // i.e 1 mil. init. supply
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
        tokens_qiara_access: TokensQiaraAccess,
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
        tokenTo: String,
        chainTo: String,
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
            move_to(admin, Permissions { tokens_omnichain_access: TokensOmnichain::give_access(admin), tokens_qiara_access: TokensQiara::give_access(admin)});
        };
    }

// === ENTRY FUNCTIONS === //
    public entry fun inits(admin: &signer){
        //         tttta(0);
        init_token(admin, utf8(b"Ethereum"), utf8(b"QETH"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/ethereum.webp"), 1_438_269_983, 1, 120_698_129, 120_698_129, 120_698_129, 1);
        init_token(admin, utf8(b"Bitcoin"), utf8(b"QBTC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/bitcoin.webp"), 1_231_006_505, 0, 21_000_000, 19_941_253, 19_941_253, 1);
         //         tttta(1);
        init_token(admin, utf8(b"Monad"), utf8(b"QMON"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/monad.webp"), 1_584_316_800, 10, 614_655_961, 559_139_255, 614_655_961, 1);
        init_token(admin, utf8(b"Sui"), utf8(b"QSUI"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/sui.webp"), 1_683_062_400, 90, 10_000_000_000, 3_680_742_933, 10_000_000_000, 1);
   //     tttta(99);
        init_token(admin, utf8(b"Deepbook"), utf8(b"QDEEP"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/deepbook.webp"),  1_683_072_000, 491, 10_000_000_000, 4_368_147_611, 10_000_000_000, 1);
        //     tttta(2);
        init_token(admin, utf8(b"Virtuals"), utf8(b"QVIRTUALS"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/virtuals.webp"), 1_614_556_800, 524, 1_000_000_000, 656_082_020, 1_000_000_000, 1);
        init_token(admin, utf8(b"Supra"), utf8(b"QSUPRA"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/supra.webp"), 1_732_598_400, 500, 100_000_000_000, 21_000_700_000, 80_600_180_397, 1);
        init_token(admin, utf8(b"USDT"), utf8(b"QUSDT"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdt.webp"), 0, 47, 185_977_352_465, 185_977_352_465, 185_977_352_465, 255);
        init_token(admin, utf8(b"USDC"), utf8(b"QUSDC"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdc.webp"), 0, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 255);   
        init_token(admin, utf8(b"Qiara"), utf8(b"QIARA"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/qiara.webp"), 0, 0, 0, 0, 0, 1);   

        init_token(admin, utf8(b"AUSD"), utf8(b"QAUSD"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/ausd.webp"), 0, 47, 175_036_043, 175_036_043, 175_036_043, 255);
        init_token(admin, utf8(b"earnAUSD"), utf8(b"QearnAUSD"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/earnAUSD.webp"), 0, 47, 0, 0, 0, 254);
        init_token(admin, utf8(b"USDT0"), utf8(b"QUSDT0"), utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/usdt0.webp"), 0, 47, 0, 0, 0, 255);


    }


    public entry fun init_depo(signer: &signer) acquires ManagedFungibleAsset, Permissions{
        ma_drilla_lul(signer, utf8(b"Ethereum"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Ethereum"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Ethereum"), utf8(b"Monad"));
        ma_drilla_lul(signer, utf8(b"Ethereum"), utf8(b"Ethereum"));
    
        ma_drilla_lul(signer, utf8(b"USDC"), utf8(b"Ethereum"));
        ma_drilla_lul(signer, utf8(b"USDT"), utf8(b"Ethereum"));
        ma_drilla_lul(signer, utf8(b"Virtuals"), utf8(b"Ethereum"));
      //  tttta(10101);
        ma_drilla_lul(signer, utf8(b"Sui"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Deepbook"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Monad"), utf8(b"Monad"));
        ma_drilla_lul(signer, utf8(b"USDC"), utf8(b"Monad"));
        ma_drilla_lul(signer, utf8(b"USDT0"), utf8(b"Monad"));
        ma_drilla_lul(signer, utf8(b"AUSD"), utf8(b"Monad"));
        ma_drilla_lul(signer, utf8(b"earnAUSD"), utf8(b"Monad"));

      //  tttta(10101);
        ma_drilla_lul(signer, utf8(b"Bitcoin"), utf8(b"Monad"));
        ma_drilla_lul(signer, utf8(b"Bitcoin"), utf8(b"Ethereum"));
        ma_drilla_lul(signer, utf8(b"Bitcoin"), utf8(b"Sui"));
      //  tttta(10101);
        ma_drilla_lul(signer, utf8(b"Virtuals"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"Supra"), utf8(b"Supra"));
        ma_drilla_lul(signer, utf8(b"USDT"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"USDC"), utf8(b"Base"));
        ma_drilla_lul(signer, utf8(b"USDC"), utf8(b"Sui"));
        ma_drilla_lul(signer, utf8(b"Qiara"), utf8(b"Supra"));
        //        tttta(9);
    }

    fun ma_drilla_lul(signer:&signer, token: String, chain: String) acquires ManagedFungibleAsset, Permissions{
        ensure_safety(token, chain);

        //tttta(7);
        let fa = mint(token, chain, INIT_SUPPLY, give_permission(&give_access(signer)));
        let asset = get_metadata(token);
        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),asset);
        //tttta(1);
        deposit(store, fa, chain);
        //tttta(123);
    }


    //115792089237316195423570985008687907853269984665640564039457584007913129639935


    fun init_token(admin: &signer, name: String, symbol: String, icon: String, creation: u64,oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8 ){
        let constructor_ref = &object::create_named_object(admin, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(name))); // Ethereum -> Qiara31 Ethereum
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
         //           tttta(111109);
        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);

        let metadata_object_signer = object::generate_signer(constructor_ref);


       // tttta(109);
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(name))); // Ethereum -> Qiara31 Ethereum
        assert!(fungible_asset::is_untransferable(asset),1);
        let sign_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(admin),asset);

        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the FA coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV2"),
            string::utf8(b"c_deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTokensCoreV2"),
            string::utf8(b"c_withdraw"),
        );
   
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );
   
        move_to(&metadata_object_signer,ManagedFungibleAsset { transfer_ref, burn_ref, mint_ref }); // <:!:initialize
        TokensMetadata::create_metadata(admin, name, creation, oracleID, max_supply, circulating_supply, total_supply, stable);
        if(symbol == utf8(b"QIARA")){
            TokensQiara::init_qiara(admin);
        }
    }
// === PUBLIC FUNCTIONS === //
    public fun deposit<T: key>(store: Object<T>,fa: FungibleAsset, chain: String) acquires Permissions, ManagedFungibleAsset{
        internal_deposit<T>(store, fa, chain, authorized_borrow_refs((fungible_asset::name(fungible_asset::store_metadata(store)))));
    }
    public fun withdraw<T: key>(store: Object<T>,amount: u64, chain: String): FungibleAsset acquires Permissions, ManagedFungibleAsset {
        internal_withdraw<T>(store, amount, chain, authorized_borrow_refs((fungible_asset::name(fungible_asset::store_metadata(store)))))
    }
 
// === INTERNAL FUNCTIONS === //
    fun internal_deposit<T: key>(store: Object<T>,fa: FungibleAsset, chain: String, managed: &ManagedFungibleAsset) acquires Permissions{
        //tttta(12);
        ChainTypes::ensure_valid_chain_name(chain);
        fungible_asset::set_frozen_flag(&managed.transfer_ref, store, true);
        if(fungible_asset::amount(&fa) == 0){
           fungible_asset::destroy_zero(fa);
           return
        };
        //tttta(1000);
        TokensOmnichain::change_UserTokenSupply(fungible_asset::name(fungible_asset::store_metadata(store)), chain,  bcs::to_bytes(&object::owner(store)), fungible_asset::amount(&fa), true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        //tttta(147);
        fungible_asset::deposit_with_ref(&managed.transfer_ref, store, fa);
    }
    fun internal_withdraw<T: key>(store: Object<T>,amount: u64, chain: String, managed: &ManagedFungibleAsset): FungibleAsset acquires Permissions {
        ChainTypes::ensure_valid_chain_name(chain);
        fungible_asset::set_frozen_flag(&managed.transfer_ref, store, true);
        if(fungible_asset::name(fungible_asset::store_metadata(store)) == utf8(b"QIARA")){
            let fee = calculate_qiara_fees(amount);
             //   tttta(fee); // aborts
            if(fee >= amount){ // amount is going to be 0 - CHECK FAILS?
                amount = 0;
                TokensOmnichain::change_UserTokenSupply(fungible_asset::name(fungible_asset::store_metadata(store)), chain, bcs::to_bytes(&object::owner(store)), fee, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
                fungible_asset::burn(&managed.burn_ref, fungible_asset::withdraw_with_ref(&managed.transfer_ref, store, fee));               
            } else {
                amount = amount - fee;
                TokensOmnichain::change_UserTokenSupply(fungible_asset::name(fungible_asset::store_metadata(store)), chain, bcs::to_bytes(&object::owner(store)), amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
                fungible_asset::burn(&managed.burn_ref, fungible_asset::withdraw_with_ref(&managed.transfer_ref, store, fee));
            };
            return fungible_asset::withdraw_with_ref(&managed.transfer_ref, store, amount)
        };

        TokensOmnichain::change_UserTokenSupply(fungible_asset::name(fungible_asset::store_metadata(store)), chain, bcs::to_bytes(&object::owner(store)), amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        return fungible_asset::withdraw_with_ref(&managed.transfer_ref, store, amount)
    }
    fun internal_mint(symbol: String, chain: String, amount: u64, managed: &ManagedFungibleAsset): FungibleAsset acquires Permissions {
        TokensOmnichain::change_TokenSupply(symbol, chain,amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        return fungible_asset::mint(&managed.mint_ref, amount)
    }

    fun internal_burn(symbol: String, chain: String, fa: FungibleAsset, managed: &ManagedFungibleAsset) acquires Permissions {
        TokensOmnichain::change_TokenSupply(symbol, chain,fungible_asset::amount(&fa), false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        fungible_asset::burn(&managed.burn_ref, fa);
    }
 
// === OVERWRITE FUNCTIONS === //
    public fun c_deposit<T: key>(store: Object<T>,fa: FungibleAsset, transfer_ref: &TransferRef) {
        fungible_asset::set_frozen_flag(transfer_ref, store, true);
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }
    public fun c_withdraw<T: key>(store: Object<T>,amount: u64, transfer_ref: &TransferRef): FungibleAsset {
        fungible_asset::set_frozen_flag(transfer_ref, store, true);
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount)
    }

// === TOKENOMICS FUNCTIONS === //
    /// Anyone can call this to burn their own tokens.
    public entry fun burn(signer: &signer, symbol: String, chain: String, amount: u64) acquires Permissions, ManagedFungibleAsset {
        let wallet = primary_fungible_store::primary_store(signer::address_of(signer), get_metadata(symbol));
        let managed = authorized_borrow_refs(symbol);
        let fa = internal_withdraw(wallet, amount, chain, managed);
        internal_burn(symbol, chain, fa, managed);
    }

    public fun burn_fa(symbol: String, chain: String, fa: FungibleAsset, cap: Permission) acquires Permissions, ManagedFungibleAsset {
        internal_burn(symbol, chain, fa, authorized_borrow_refs(symbol))
    }
    // Only allowed modules are allowed to call mint function, 
    // in this scenario we allow only the module bridge_handler to be able to call this function.
    public fun mint(symbol: String, chain: String, amount: u64, cap: Permission): FungibleAsset acquires Permissions, ManagedFungibleAsset {
        internal_mint(symbol, chain, amount, authorized_borrow_refs(symbol))
    }

    public fun mint_to(address: address, symbol: String, chain: String, amount: u64, cap: Permission) acquires Permissions, ManagedFungibleAsset {
        let asset = get_metadata(symbol);
        let managed = authorized_borrow_refs(symbol);
        let fa = internal_mint(symbol, chain, amount, managed);
        let to = primary_fungible_store::ensure_primary_store_exists(address,asset);
        internal_deposit(to, fa, chain, managed);
    }

    public entry fun transfer(sender:&signer, to: address, symbol: String, chain: String, amount: u64) acquires ManagedFungibleAsset,Permissions {
        ensure_safety(symbol, chain);
        let asset = get_metadata(symbol);
        TokensOmnichain::ensure_token_supports_chain(symbol, chain);
        let managed = authorized_borrow_refs(symbol);
        if(!account::exists_at(to)){
            let wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
            let fa = internal_withdraw(wallet, amount, chain, managed);
            fungible_asset::burn(&managed.burn_ref, fa);
            TokensOmnichain::change_UserTokenSupply(symbol, chain, bcs::to_bytes(&to), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            return
        };

        let from = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
        let to = primary_fungible_store::ensure_primary_store_exists(to,asset);

        
        let fa = internal_withdraw(from, amount, chain, managed);
        internal_deposit(to, fa, chain, managed);
    }

    public entry fun request_bridge(user: &signer, symbol: String, chain: String, provider: String, amount: u64, tokenTo: String, receiver: vector<u8>) acquires Permissions, ManagedFungibleAsset{
        ensure_safety(symbol, chain);
        ProviderTypes::ensure_valid_provider(provider, chain);
        let managed = authorized_borrow_refs(symbol);
        let wallet = primary_fungible_store::primary_store(signer::address_of(user), get_metadata(symbol));
        let fa = internal_withdraw(wallet, amount, chain, managed);

        let nonce = Nonce::return_user_nonce(bcs::to_bytes(&signer::address_of(user)));

        let legit_amount = (TokensOmnichain::return_address_balance_by_chain_for_token(bcs::to_bytes(&signer::address_of(user)), chain, symbol) as u64);
        assert!(legit_amount >= amount, ERROR_SUFFICIENT_BALANCE);
        let total_outflow = (TokensOmnichain::return_address_outflow_by_chain_for_token(bcs::to_bytes(&signer::address_of(user)), chain, symbol) as u64);

        TokensOmnichain::change_UserTokenSupply(symbol, chain, bcs::to_bytes(&signer::address_of(user)), amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        TokensOmnichain::increment_UserOutflow(symbol, chain, bcs::to_bytes(&receiver), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        internal_deposit(Storages::return_lock_storage(symbol, chain), fa, chain,managed);
        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(user))),
            Event::create_data_struct(utf8(b"receiver"), utf8(b"vector<u8>"), bcs::to_bytes(&receiver)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"total_outflow"), utf8(b"u64"), bcs::to_bytes(&total_outflow)),
            Event::create_data_struct(utf8(b"additional_outflow"), utf8(b"u64"), bcs::to_bytes(&amount)),
        ];
        Event::emit_consensus_event(utf8(b"Request Bridge"), data, utf8(b"zk"));

    
    }

// === PERMISSIONELESS FUNCTIONS === // - for permissioneless access across chains
    public fun p_transfer(validator: &signer, sender: vector<u8>, to: vector<u8>, symbol: String, chain: String, amount: u64, perm: Permission) acquires Permissions {
        ensure_safety(symbol, chain);
        TokensOmnichain::change_UserTokenSupply(symbol, chain, sender, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        TokensOmnichain::change_UserTokenSupply(symbol, chain, to, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 

    }

    // Function to pre-"burn" tokens when bridging out, but the transaction isnt yet validated so the tokens arent really burned yet.
    // Later implement function to claim locked tokens if the bridge tx fails
    public fun p_request_bridge(validator: &signer, user: vector<u8>, symbol: String, chain: String, provider: String, amount: u64, receiver: vector<u8>,perm: Permission) acquires Permissions{
        ensure_safety(symbol, chain);
        ProviderTypes::ensure_valid_provider(symbol, chain);
        let legit_amount = (TokensOmnichain::return_address_balance_by_chain_for_token(user, chain, symbol) as u64);
        assert!(legit_amount >= amount, ERROR_SUFFICIENT_BALANCE);
        let total_outflow = (TokensOmnichain::return_address_outflow_by_chain_for_token(bcs::to_bytes(&user), chain, symbol) as u64);
       
        let nonce = Nonce::return_user_nonce(bcs::to_bytes(&user));
        TokensOmnichain::change_UserTokenSupply(symbol, chain, user, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
        TokensOmnichain::increment_UserOutflow(symbol, chain, bcs::to_bytes(&receiver), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 

        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"receiver"), utf8(b"vector<u8>"), bcs::to_bytes(&receiver)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"total_outflow"), utf8(b"u64"), bcs::to_bytes(&total_outflow)),
            Event::create_data_struct(utf8(b"additional_outflow"), utf8(b"u64"), bcs::to_bytes(&amount)),
        ];
        Event::emit_consensus_event(utf8(b"Request Bridge"), data, utf8(b"zk"));

    }

    /*    
    public fun bridged(validator: &signer, user: address, symbol: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        ensure_safety(symbol, chain);

        if(!account::exists_at(user)){
            TokensOmnichain::change_UserTokenSupply(symbol, chain, bcs::to_bytes(&user), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            TokensOmnichain::change_TokenSupply(symbol, chain,amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
            
            event::emit(BridgedEvent {
                address: bcs::to_bytes(&user),
                token: symbol,
                chain: chain,
                amount: amount,
                time: timestamp::now_seconds() 
            });
            return
        };
     
        let asset = get_metadata(symbol);
        let managed = authorized_borrow_refs(symbol);
        let fa = internal_mint(symbol, chain, amount, managed);

        let store = primary_fungible_store::ensure_primary_store_exists(user,asset);
        internal_deposit(store, fa, chain, managed);
    
        event::emit(BridgedEvent {
            address: bcs::to_bytes(&user),
            token: symbol,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
    
    }
    */
// === CONSENSUS FUNCTIONS === //
    public fun c_finalize_bridge(validator: &signer, symbol: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        ensure_safety(symbol, chain);
    
        let managed = authorized_borrow_refs(symbol);
        let fa = internal_withdraw(Storages::return_lock_storage(symbol, chain), amount, chain, managed);

        TokensOmnichain::change_TokenSupply(symbol, chain, fungible_asset::amount(&fa), false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        fungible_asset::burn(&managed.burn_ref, fa);
    
        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"string"), bcs::to_bytes(&amount)),
        ];
        Event::emit_bridge_event(utf8(b"Finalized Bridge from Supra"), data, utf8(b"none"));    

    }

    public fun c_bridge_to_supra(validator: &signer, user: vector<u8>, symbol: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        ensure_safety(symbol, chain);
    

        if(vector::length(&user) == 33){
             if(account::exists_at(from_bcs::to_address(user))){
                 mint_to(from_bcs::to_address(user), symbol, chain, amount, perm);
                 // the token supply change & user token supply change is already implemented in mint_to
             };
        } else {
            TokensOmnichain::change_UserTokenSupply(symbol, chain, user, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            TokensOmnichain::change_TokenSupply(symbol, chain, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
        };

    
        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"address"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"user"), utf8(b"vector<u8>"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"string"), bcs::to_bytes(&amount)),
        ];
        Event::emit_bridge_event(utf8(b"Finalized Bridge to Supra"), data, utf8(b"none"));    

    }

    public fun c_finalize_failed_bridge(validator: &signer, user: address, symbol: String, chain: String, amount: u64, perm: Permission) acquires Permissions, ManagedFungibleAsset{
        ensure_safety(symbol, chain);
        let managed = authorized_borrow_refs(symbol);

        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"string"), bcs::to_bytes(&amount)),
        ];
        Event::emit_bridge_event(utf8(b"Finalized Failed Bridge"), data, utf8(b"none"));   

        if(!account::exists_at(user)){
            TokensOmnichain::change_UserTokenSupply(symbol, chain, bcs::to_bytes(&user), amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
            TokensOmnichain::change_TokenSupply(symbol, chain,amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access));
            
            return
        };
     
        let asset = get_metadata(symbol);
        let fa = internal_mint(symbol, chain, amount, managed);

        let store = primary_fungible_store::ensure_primary_store_exists(user,asset);
        internal_deposit(store, fa, chain, managed);
    
    
    
    }

    // Function that can be only called by Validator, used to redeem tokens to existing Supra wallet.
    public fun redeem(validator: &signer, permissioneless_wallet: vector<u8>, supra_wallet: address, symbol:String, chain:String, perm: Permission) acquires ManagedFungibleAsset, Permissions {
        let asset = get_metadata(symbol);
        ensure_safety(symbol, chain);
        let managed = authorized_borrow_refs(symbol);
        assert!(account::exists_at(supra_wallet), ERROR_ACCOUNT_DOES_NOT_EXISTS);

        let amount = (TokensOmnichain::return_address_balance_by_chain_for_token(bcs::to_bytes(&signer::address_of(validator)), chain, symbol) as u64);
        let fa = internal_mint(symbol, chain, amount, managed);
        TokensOmnichain::change_UserTokenSupply(symbol, chain, permissioneless_wallet, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain_access)); 
      
        let wallet = primary_fungible_store::primary_store(supra_wallet, asset);
        internal_deposit(wallet, fa, chain, managed);
    }
    
    public entry fun claim_inflation(claimer: &signer) acquires Permissions, ManagedFungibleAsset  {
        TokensQiara::change_last_claim(claimer, TokensQiara::give_permission(&borrow_global<Permissions>(@dev).tokens_qiara_access));
        let asset = get_metadata(utf8(b"Qiara"));
        let claimable_amount = TokensQiara::claimable(*option::borrow(&fungible_asset::supply(asset)));
        let managed = authorized_borrow_refs(utf8(b"QIARA"));
        let delta_seconds = timestamp::now_seconds() - TokensQiara::get_last_claimed();

        let fa = internal_mint(utf8(b"Qiara"),utf8(b"Supra"),(claimable_amount as u64), managed);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(claimer),asset);
        internal_deposit(to_wallet, fa,utf8(b"Supra"), managed);

    }



    #[view]
    public fun ensure_fees(validator: address, symbol: String, chain: String, amount: u256): (u256, u256){ // change to u256 for security overflows
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(symbol);
        let tier = TokensMetadata::get_coin_metadata_tier(&metadata);
        let flat_fee = TokensTiers::flat_usd_fee(tier); // 0.0002$ -> zmenit na tak 0.001$
        let transfer_fee = TokensTiers::transfer_fee(tier); // 0.00030% > zmenit na tak 0.00005%

        //27500000000 - transfer_fee // with 1$ size
        //10004001600 - flat fee // with 1$ size
        //105530009002
        let token_value = TokensMetadata::getValueByCoin(symbol, (flat_fee as u256)*100_000_000);

        let total = (((transfer_fee as u256) * (amount*100))) + token_value;
        if(total > amount*100_000_000){
            return (amount, amount) // to ensure fee doesnt overfload the actuall amount which would cause abort errors later on.
        };

        // the +1 is here to avoid bad overall debt, because malicious users could create new permisioneless account, do some action,
        // because of the % fee, the rewards are messuered in different scale (*100_000_000)
        // so essentially the results would be (1000, 100036119502) for 1111 inputed amount, which would mean
        // that the validator actually gets higher reward than the actuall fee is which could lead to debt of unified liquidity
        // eventually creates extremely small/non-noticable deflationary pressure for the token
        return (((total/100_000_000)+1), total) 
    }

    public fun ensure_accrue_fees(validator: address, symbol: String, chain: String, amount: u256): u256{
        let (fee, validator_reward) = ensure_fees(validator, symbol, chain, amount);
        return (amount-fee)
    }
    #[view]
    public fun calculate_qiara_fees(amount: u64): u64 {
        // 500 + 100*0 = 500
        let burn_fee_bps = TokensQiara::get_burn_fee() + TokensQiara::get_burn_fee_increase() * TokensQiara::get_month();

        // scale denominator = 100_000_000 (because 1% = 1_000_000, so 100% = 100_000_000)
        let scale = 100_000_000;

        
        let burn_amount = (amount * burn_fee_bps) / scale;
        if(burn_amount == 0){
            if(TokensQiara::get_minimal_fee() > amount){
                return amount;
            } else {
            return TokensQiara::get_minimal_fee();                
            };
        };
        return burn_amount
    }


// === HELPFER FUNCTIONS === //

    fun ensure_safety(token: String, chain: String){
        ChainTypes::ensure_valid_chain_name(chain);
        TokensType::ensure_token_supported_for_chain(TokensType::convert_token_nickName_to_name(token), chain)
    }
    // Borrow the immutable reference of the refs of `metadata`.
    inline fun authorized_borrow_refs(token_name: String): &ManagedFungibleAsset acquires ManagedFungibleAsset { let asset = get_metadata(token_name); borrow_global<ManagedFungibleAsset>(object::object_address(&asset))}

// === VIEW FUNCTIONS === //
    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(symbol:String): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(symbol))); // Ethereum -> Qiara31 Ethereum
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata1(symbol:String): Object<Metadata> {
        //tttta(999);
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&symbol));
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