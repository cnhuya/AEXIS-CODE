module dev::QiaraVaultsV38 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::bcs;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::dispatchable_fungible_asset;
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};
    use supra_framework::event;

    use dev::QiaraTokensCoreV45::{Self as TokensCore, CoinMetadata};
    use dev::QiaraTokensMetadataV45::{Self as TokensMetadata, VMetadata};
    use dev::QiaraTokensSharedV45::{Self as TokensShared};
    use dev::QiaraTokensRatesV45::{Self as TokensRates, Access as TokensRatesAccess};

    use dev::QiaraMarginV53::{Self as Margin, Access as MarginAccess};

   // use dev::QiaraFeeVaultV10::{Self as fee};

    use dev::QiaraTokenTypesV27::{Self as TokensTypes};
    use dev::QiaraChainTypesV27::{Self as ChainTypes};
    use dev::QiaraProviderTypesV27::{Self as ProviderTypes};

    use dev::QiaraMathV9::{Self as QiaraMath};

    use dev::QiaraStorageV35::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV35::{Self as capabilities, Access as CapabilitiesAccess};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 99;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 3;
    const ERROR_USER_VAULT_NOT_INITIALIZED: u64 = 4;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 5;
    const ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION: u64 = 6;
    const ERROR_INVALID_COIN_TYPE: u64 = 6;
    const ERROR_BORROW_COLLATERAL_OVERFLOW: u64 = 7;
    const ERROR_INSUFFICIENT_COLLATERAL: u64 = 8;
    const ERROR_NO_PENDING_DEPOSITS_FOR_THIS_VAULT_PROVIDER: u64 = 9;
    const ERROR_NO_DEPOSITS_FOR_THIS_VAULT_PROVIDER: u64 = 10;
    const ERROR_CANT_LIQUIDATE_THIS_VAULT: u64 = 11;
    const ERROR_CANT_ACRUE_THIS_VAULT: u64 = 12;
    const ERROR_NO_VAULT_FOUND: u64 = 13;
    const ERROR_NO_VAULT_FOUND_FULL_CYCLE: u64 = 14;
    const ERROR_UNLOCK_BIGGER_THAN_LOCK: u64 = 15;
    const ERROR_NOT_ENOUGH_MARGIN: u64 = 16;
    const ERROR_INVALID_TOKEN: u64 = 17;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 18;
    const ERROR_PROVIDER_DOESNT_SUPPORT_THIS_TOKEN_ON_THIS_CHAIN: u64 = 19;


    const ERROR_A: u64 = 101;
    const ERROR_B: u64 = 102;
    const ERROR_C: u64 = 103;
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key, store, drop {
        margin: MarginAccess,
        tokens_rates: TokensRatesAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
    }

// === STRUCTS === //
   
   // Maybe in the future remove this, and move total borrowed into global vault? idk tho how would it do because of the phantom type tag
    struct Vault has key, store, copy, drop{
        total_borrowed: u256,
        balance: Object<FungibleStore>,
    }

    struct FullVault has key, store, copy, drop{
        token: String,
        total_deposited: u256,
        total_borrowed: u256,
        utilization: u64,
        lend_rate: u64,
        borrow_rate: u64
    }

    struct GlobalVault has key {
        //  token, chain, provider
        balances: Table<String,Map<String, Map<String, Vault>>>,
    }

    struct VaultUSD has store, copy, drop {
        tier: u8,
        oracle_price: u128,
        oracle_decimals: u8,
        total_deposited: u256,
        balance: u64,
        borrowed: u256,
        utilization: u256,
        rewards: u256,
        interest: u256,
        fee: u256,
    }

    struct CompleteVault has key{
        vault: VaultUSD,
        coin: CoinMetadata,
        w_fee: u64,
        Metadata: VMetadata,
    }

// === EVENTS === //
    #[event]
    struct BridgeEvent has copy, drop, store {
        validator: address,
        amount: u64,
        to: vector<u8>,
        token: String,
        chain: String,
        time: u64
    }

    #[event]
    struct BridgedDepositEvent has copy, drop, store {
        validator: address,
        amount: u64,
        from: address,
        token: String,
        chain: String,
        time: u64
    }

    #[event]
    struct VaultEvent has copy, drop, store {
        type: String,
        amount: u64,
        address: address,
        token: String,
        time: u64
    }

// === FUNCTIONS === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { balances: table::new<String, Map<String, Map<String, Vault>>>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), tokens_rates:  TokensRates::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin)});
        };
    //    init_all_vaults(admin);

    }

    public entry fun init_vault(admin: &signer, token: String, chain: String, provider: String) acquires GlobalVault {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
     
        ChainTypes::ensure_valid_chain_name(&chain);
        ProviderTypes::ensure_valid_provider(&provider);
        
        internal_ensure_storages_exists(token, chain, provider);
    }

    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.
    /// 
    /// Security:
    /// 1.Tato funkce muze byt zavolana pouze z smart modulu "bridge"
    /// 2.Signer musi minimalne X Qiara Tokenu stakovat
    public fun bridge_deposit(validator: &signer, sender: vector<u8>, recipient: vector<u8>, token: String, chain: String, provider: String, fa: FungibleAsset, lend_rate: u64, permission: Permission) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault>(@dev);
        coin::merge(&mut vault.balance, coins);

        VaultRates::change_rates(token, chain, lend_rate, VaultRates::give_permission(&borrow_global<Permissions>(@dev).vault_rates));
        Margin::add_deposit(sender, recipient, token, chain, provider, (fungible_asset::amount(&fa) as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        provider_vault.total_deposited = provider_vault.total_deposited + (fungible_asset::amount(&fa) as u256);

       // event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }
    // T - Token From
    // Y - Token To
    // X - Vault provider From
    // Z - Vault provider To
    // A - Rewards token
    // B - Interest token
    public fun bridge_swap(validator: &signer, token: String, tokenTo: String, token_reward: String, token_interest: String, permission: Permission, recipient: address, amount_in: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit(bcs::to_bytes(&signer::address_of(sender)), bcs::to_bytes(&signer::address_of(sender)), token, chain, provider, (amount_in as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        let provider_vault_from = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        provider_vault_from.total_deposited = provider_vault_from.total_deposited - (amount_in as u256);


        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = TokensMetadata::get_coin_metadata_by_symbol(token);
        let metadata_out = TokensMetadata::get_coin_metadata_by_symbol(tokenTo);

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u256) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit(bcs::to_bytes(&signer::address_of(sender)), bcs::to_bytes(&signer::address_of(sender)), tokenTo, chain, provider, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        let provider_vault_to = find_vault(borrow_global_mut<GlobalVault>(@dev), tokenTo, chain, provider); 
        provider_vault_to.total_deposited = provider_vault_to.total_deposited + (amount_out as u256);


        accrue(signer::address_of(user), token, chain, provider);
    }
    /// log event emmited in this function in backend and add it to registered events in chains.move
    /// this is needed in case validators could overfetch multiple times this event and that way unlock multiple times on other chains
    /// from locked vaults
    public entry fun bridge(user: &signer, destination_address: vector<u8>, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
       // let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);
 

        //let type_str = type_info::type_name<T>();
        //let user_vault = find_or_insert(&mut user_vault_list.list, type_str);


        accrue(signer::address_of(user), token, chain, provider);
        CoinTypes::deposit<Token>(user, amount);
        
       // assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
       // assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

       // let coins = coin::extract(&mut vault.balance, amount);
       // coin::deposit(signer::address_of(user), coins);

       // vault.total_deposited = vault.total_deposited - amount;
       // user_vault.deposited = user_vault.deposited - amount;

       // accrue<T>(user_vault);
        event::emit(BridgeEvent { amount, validator: signer::address_of(user), token: type_info::type_name<Token>(), to: destination_address, chain: ChainTypes::convert_chainType_to_string<Chain>(), time: timestamp::now_seconds() });
    }


    public entry fun swap(signer: &signer, token: String, chain: String, provider:String, amount: u64, tokenTo: String, token_reward: String, token_interest: String,) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit(signer::address_of(user), (amount_in as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_from = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        provider_vault_from.total_deposited = provider_vault_from.total_deposited - (amount_in as u256);


        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = TokensMetadata::get_coin_metadata_by_symbol(token);
        let metadata_out = TokensMetadata::get_coin_metadata_by_symbol(tokenTo);

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u256) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit<Token, Market>(signer::address_of(user), (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_to = find_vault(borrow_global_mut<GlobalVault>(@dev), tokenTo, chain, provider); 
        provider_vault_to.total_deposited = provider_vault_to.total_deposited + (amount_out as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
    }

    public entry fun deposit(sender: &signer, to: vector<u8>, token: String, chain: String, provider: String, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let fa = TokensCore::withdraw(primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),get_metadata(symbol)), amount, chain);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        TokensCore::deposit(provider_vault.balance, fa, chain);
        Margin::add_deposit(to, bcs::to_bytes(&signer::address_of(sender)), token, chain, provider, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        accrue(signer::address_of(user), token, chain, provider);
       // event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }

    public entry fun withdraw(sender: &signer, to: address, token: String, chain: String, provider: String, amount: u64, token_reward: String, token_interest: String) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        let fa = TokensCore::withdraw(provider_vault.balance, amount, chain);

        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(to,get_metadata(symbol)), fa, chain);

      //  let fee_amount = VerifiedTokens::get_coin_metadata_market_w_fee(&TokensMetadata::get_coin_metadata_by_symbol(token)) * (amount as u64) / 1000000;
      //  fee::pay_fee<Token>(user, coin::withdraw<Token>(user, fee_amount), utf8(b"Withdraw Fee"));

        Margin::remove_deposit(bcs::to_bytes(&to), bcs::to_bytes(&signer::address_of(sender)), tokenTo, chain, provider, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        rt(signer::address_of(sender), token, chain, provider);
       // event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }

    public entry fun borrow(sender: &signer, to: address, token: String, chain: String, provider: String, amount: u64, token_reward: String, token_interest: String) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

    //    let valueUSD = getValue(token, (amount as u256));
    //    let (depoUSD, _, _, borrowUSD, _, _, _, _, _, _) = Margin::get_user_total_usd(signer::address_of(sender));

    //    assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);
    //    assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        let fa = TokensCore::withdraw(provider_vault.balance, amount, chain);
        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(to,get_metadata(symbol)), fa, chain);

        Margin::add_borrow(bcs::to_bytes(&to), bcs::to_bytes(&signer::address_of(sender)), tokenTo, chain, provider, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        provider_vault.total_borrowed = provider_vault.total_borrowed + (amount as u256);

        accrue(signer::address_of(user), token, chain, provider);
       // event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }


    public entry fun repay(sender: &signer, token: String, chain: String, provider: String, amount: u64, token_reward: String, token_interest: String) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        let fa = TokensCore::withdraw(primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),get_metadata(token)), amount, chain);
        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(to,get_metadata(symbol)), fa, chain);

        Margin::remove_borrow(bcs::to_bytes(&signer::address_of(sender)), bcs::to_bytes(&signer::address_of(sender)), tokenTo, chain, provider, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        provider_vault.total_borrowed = provider_vault.total_borrowed - (amount as u256);

        accrue(signer::address_of(user), token, chain, provider);
        // event::emit(VaultEvent { type: utf8(b"Repay"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }

    /*public entry fun claim_rewards<Token, TokenReward, TokenInterest>(user: &signer) acquires GlobalVault, Permissions {
        let addr = signer::address_of(user);
        let type_str = type_info::type_name<Token>();

        accrue(signer::address_of(user), token, chain, provider);
        let (rate, reward_index, interest_index, last_updated) = VaultRates::get_vault_raw(type_info::type_name<Token>());
        //        return (balance.token, balance.deposited, balance.borrowed, balance.reward_index_snapshot, balance.interest_index_snapshot, balance.last_update)
        let (_,user_deposited, user_borrowed, user_rewards, _, user_interest, _, _) = Margin::get_user_raw_balance<Token, Market>(signer::address_of(user));

        let reward_amount = user_rewards;
        let interest_amount = user_interest;

        Margin::remove_interest<Token, Market>(signer::address_of(user), (interest_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards<Token, Market>(signer::address_of(user), (reward_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let global_vault = borrow_global_mut<GlobalVault<Token>>(@dev);

        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(coin::value(&global_vault.balance) >= (reward as u64), ERROR_NOT_ENOUGH_LIQUIDITY);
            let coins = coin::extract(&mut global_vault.balance, (reward as u64));
            coin::deposit(addr, coins);
            event::emit(VaultEvent { type: utf8(b"Claim Rewards"), amount: (reward as u64), address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            //Margin::remove_balance<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
            //deposited.deposited = deposited.deposited - interest;

            event::emit(VaultEvent {  type: utf8(b"Pay Rewards"), amount: (interest as u64), address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() }); 
        }

    }*/

    // gets value by usd
    #[view]
    public fun getValue(resource: String, amount: u256): u256{
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracleID(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / VerifiedTokens::get_coin_metadata_denom(&metadata)
    }

    // converts usd back to coin value
    #[view]
    public fun getValueByCoin(resource: String, amount: u256): u256{
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(resource);
        //abort(100);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracleID(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return (((amount as u256)* VerifiedTokens::get_coin_metadata_denom(&metadata)) / (price as u256))
    }

    #[view]
    public fun get_utilization_ratio(deposited: u256, borrowed: u256): u256 {
        //abort(147);
        if (deposited == 0 || borrowed == 0) {
            0
        } else {
            ((borrowed * 100_000_000) / deposited)
        }
    }



    #[view]
    public fun return_vaults_for_token(token: String): Map<String, Map<String, Vault>> acquires GlobalVault {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vaults = borrow_global<GlobalVault>(@dev);

        if (!table::contains(&vaults.balances, token)) {
            ERROR_INVALID_TOKEN
        };

        *table::borrow(&vaults.balances, token);
    }


    #[view]
    public fun return_vaults_for_token_on_chain(token: String, chain: String): Map<String, Vault> acquires GlobalVault {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vaults = borrow_global<GlobalVault>(@dev);

        if (!table::contains(&vaults.balances, token)) {
            abort ERROR_INVALID_TOKEN
        };
        
        let token_table = table::borrow(&vaults.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

       *map::borrow(&lock_storage.balances, &chain);
    }


    #[view]
    public fun return_vaults_for_token_on_chain_with_provider(token: String, chain: String, provider: String): Vault acquires GlobalVault {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vaults = borrow_global<GlobalVault>(@dev);

        if (!table::contains(&vaults.balances, token)) {
            abort ERROR_INVALID_TOKEN
        };
        
        let token_table = table::borrow(&vaults.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

        let chain_map = map::borrow(&token_table, &chain);

        if (!map::contains_key(chain_table, &provider)) {
            abort ERROR_PROVIDER_DOESNT_SUPPORT_THIS_TOKEN_ON_THIS_CHAIN
        };

        map::borrow(chain_map, &provider);
    }


/*    #[view]
    public fun get_complete_vault<T, X:store>(tokenStr: String,): CompleteVault acquires GlobalVault {
        let vault = get_vaultUSD<T>(tokenStr);
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);;
        CompleteVault { vault: vault, coin: CoinTypes::get_coin_data<T>(), w_fee: VerifiedTokens::get_coin_metadata_market_w_fee(&metadata), Metadata: metadata  }
    }


    #[view]
    public fun get_vault_raw(vaultStr: String): (String, u256, u256,u256) acquires VaultRegistry {
        let vault = table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, vaultStr);
        (vault.token, vault.total_deposited, vault.total_borrowed, vault.locked)
    }

    #[view]
    public fun get_vaultUSD<T>(tokenStr: String): VaultUSD acquires GlobalVault, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        let balance = coin::value(&vault.balance);
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);

        let vault_total = get_vault(tokenStr);
        let utilization = get_utilization_ratio(vault_total.total_deposited, vault_total.total_borrowed);

        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracleID(&metadata));

        let (lend_apy, _, _) = QiaraMath::compute_rate(
                utilization,
                (VerifiedTokens::get_coin_metadata_market_rate(&metadata) as u256),
                (VerifiedTokens::get_coin_metadata_rate_scale(&metadata, true) as u256), // pridat check jestli to je borrow nebo lend
                true,
                5
            );

        let (borrow_apy, _, _) = QiaraMath::compute_rate(
                utilization,
                (VerifiedTokens::get_coin_metadata_market_rate(&metadata) as u256),
                (VerifiedTokens::get_coin_metadata_rate_scale(&metadata, false) as u256), // pridat check jestli to je borrow nebo lend
                false,
                5
            );
       
        VaultUSD {tier: VerifiedTokens::get_coin_metadata_tier(&metadata), oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: vault_total.total_deposited,balance: balance, borrowed: vault_total.total_borrowed, utilization: utilization, rewards: lend_apy, interest: borrow_apy, fee: get_withdraw_fee(utilization)}
    }*/


    #[view]
    public fun get_withdraw_fee(utilization: u256): u256 {
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(u_bps2 > 10000){
            u_bps2 = 10000;
        };
        let bonus = ((u_bps) * 4_000) / (20000 - u_bps2);
        return (bonus as u256)
    }

    fun tttta(number: u64){
        abort(number);
    }


    public fun accrue(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, token_reward: String, token_interest: String) acquires GlobalVault, Permissions {
        // staci fetchovat jen jeden vault teoreticky? protoze z nej poterbuju ty rewards a interests indexy? a to pak previst na token A a B... ?
        let (lend_rate, reward_index, interest_index, last_updated) = VaultRates::get_vault_raw(token, chain); // CHECK
        let vault = get_vault(token); 

        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);

        let utilization = get_utilization_ratio(vault.total_deposited, vault.total_borrowed);

        VaultRates::accrue_global(token, chain, (lend_rate as u256), (VerifiedTokens::get_coin_metadata_rate_scale((&metadata), false) as u256), (utilization as u256), (get_balance_amount<Token>() as u256), (vault.total_borrowed as u256), VaultRates::give_permission(&borrow_global<Permissions>(@dev).vault_rates));

        let scale: u128 = 1_000_000;
        let (_,user_deposited, user_borrowed, user_rewards,user_reward_index, user_interest, user_interest_index, _) = Margin::get_user_raw_balance(user, token, chain, provider); // CHECK


        if ((reward_index) > (user_reward_index as u128)) {
            let delta_reward = reward_index - (user_reward_index as u128);

            if((((user_deposited as u128) * delta_reward) / scale) > 0){
                let user_delta_reward_value  = ((((user_deposited as u128) * delta_reward) / scale) as u256);
                let receive_rewards_in_A_tokens = getValueByCoin(token_reward, getValue(token, user_delta_reward_value));
                Margin::add_rewards(user, (receive_rewards_in_A_tokens as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_reward_index(user, (reward_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_time(user, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
        };

        if ((interest_index) > (user_interest_index as u128)) {

            let delta_interest = interest_index - (user_interest_index as u128);
            if((((user_borrowed as u128) * delta_interest) / scale) > 0){
                let user_delta_interest_value = ((((user_borrowed as u128) * delta_interest) / scale) as u256);

                let pay_interest_in_B_tokens = getValueByCoin(token_interest, getValue(token, user_delta_interest_value));
                Margin::add_interest(user, (pay_interest_in_B_tokens as u256) , Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_interest_index(user, (interest_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_time(user, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
        }; 
    }
    // Initialize storages for a specific token and chain
    fun find_vault(vaults: &mut GlobalVault, token: String, chain: String, provider: String): &mut Vault acquires GlobalVault {
        ChainTypes::ensure_valid_chain_name(&chain);
        
        let metadata = TokensRouter::get_metadata(token);

        if (!table::contains(&vaults.balances, token)) {
            table::add(&mut vaults.balances, token, map::new<String, Map<String,Vault>>());
        };
        let borrow_mut = table::borrow_mut(&mut lock_storage.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            map::add( token_table, chain, map::new<String, Vault>());
        };

        let chain_map = map::borrow_mut(&mut lock_storage.balances, &chain);

        if (!map::contains_key(chain_table, &provider)) {
            map::add( chain_table, provider, Vault {total_borrowed: 0, balance: primary_fungible_store::ensure_primary_store_exists<Metadata>(@dev, metadata)});
        };

        map::borrow(chain_map, &provider);
    }
}
