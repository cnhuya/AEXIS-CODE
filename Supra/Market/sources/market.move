module dev::QiaraVaultsV15 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::option::{Option};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::coin::{Self, Coin};
    use supra_framework::supra_coin::{Self, SupraCoin};
    use supra_framework::event;

    use dev::QiaraVerifiedTokensV12::{Self as VerifiedTokens, Tier, CoinData, Metadata, Access as VerifiedTokensAccess};
    use dev::QiaraMarginV24::{Self as Margin, Access as MarginAccess};

    use dev::QiaraCoinTypesV5::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use dev::QiaraChainTypesV5::{Self as ChainTypes};
    use dev::QiaraVaultTypesV5::{Self as VaultTypes, Access as VaultTypesAccess, None, AlphaLend, SuiLend, Moonwell};
    use dev::QiaraFeatureTypesV5::{Market};

    use dev::QiaraMathV9::{Self as QiaraMath};

    use dev::QiaraStorageV24::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV24::{Self as capabilities, Access as CapabilitiesAccess};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 2;
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
        vault_types: VaultTypesAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
        verified_tokens: VerifiedTokensAccess,
    }

// === STRUCTS === //
   
    struct Vault has key, store, copy, drop{
        provider: String,
        total_deposited: u128,
        total_borrowed: u128,
    }


    struct FullVault has key, store, copy, drop{
        provider: String,
        total_deposited: u128,
        total_borrowed: u128,
        utilization: u64,
        lend_rate: u64,
        borrow_rate: u64
    }


    struct VaultRegistry has key {
        vaults: table::Table<String, vector<Vault>>,
    }

    struct GlobalVault<phantom T> has key {
        tier: u8,
        balance: coin::Coin<T>,
    }

    struct VaultUSD has store, copy, drop {
        tier: u8,
        oracle_price: u128,
        oracle_decimals: u8,
        total_deposited: u128,
        balance: u64,
        borrowed: u128,
        utilization: u64,
        rewards: u256,
        interest: u256,
        fee: u64,
    }

    struct CompleteVault has key{
        vault: VaultUSD,
        coin: CoinData,
        tier: Tier,
        Metadata: Metadata,
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
    fun init_module(admin: &signer) acquires Permissions, VaultRegistry{
        if (!exists<VaultRegistry>(@dev)) {
            move_to(admin, VaultRegistry {vaults: table::new<String, vector<Vault>>()});
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), vault_types:  VaultTypes::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin), verified_tokens:  VerifiedTokens::give_access(admin)});
        };
        init_all_vaults(admin);
        init_all_providers(admin);
    }

    public fun init_all_vaults(address: &signer) acquires Permissions{
        init_vault<BaseEthereum>(address, 1, 1, utf8(b"Base"));
        init_vault<BaseUSDC>(address, 0, 47,  utf8(b"Base"));

        init_vault<SuiEthereum>(address, 1, 1,  utf8(b"Sui"));
        init_vault<SuiUSDC>(address, 0, 47, utf8(b"Sui"));
        init_vault<SuiUSDT>(address, 0, 47, utf8(b"Sui"));
        init_vault<SuiSui>(address, 2, 90, utf8(b"Sui"));
        init_vault<SuiBitcoin>(address, 1, 0, utf8(b"Sui"));

        init_vault<SupraCoin>(address, 3, 500, utf8(b"Supra"));
    }

    public entry fun init_all_providers(address: &signer) acquires VaultRegistry{
        init_provider<BaseEthereum, None>(address);
        init_provider<BaseEthereum, Moonwell>(address);

        init_provider<BaseUSDC, None>(address);
        init_provider<BaseUSDC, Moonwell>(address);

        init_provider<SupraCoin, None>(address);

        init_provider<SuiEthereum, None>(address);
        init_provider<SuiUSDC, None>(address);
        init_provider<SuiUSDT, None>(address);
        init_provider<SuiSui, None>(address);
        init_provider<SuiBitcoin, None>(address);

        init_provider<SuiEthereum, AlphaLend>(address);
        init_provider<SuiUSDC, AlphaLend>(address);
        init_provider<SuiUSDT, AlphaLend>(address);
        init_provider<SuiSui, AlphaLend>(address);
        init_provider<SuiBitcoin, AlphaLend>(address);

        init_provider<SuiEthereum, SuiLend>(address);
        init_provider<SuiUSDC, SuiLend>(address);
        init_provider<SuiUSDT, SuiLend>(address);
        init_provider<SuiSui, SuiLend>(address);
        init_provider<SuiBitcoin, SuiLend>(address);

    }

    public entry fun init_provider<T, X>(admin: &signer) acquires VaultRegistry {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let registry = borrow_global_mut<VaultRegistry>(@dev);
        let token_key = type_info::type_name<T>();

        // If no entry exists for this token, initialize with an empty vector
        if (!table::contains(&registry.vaults, token_key)) {
            table::add(&mut registry.vaults, token_key, vector::empty<Vault>());
        };

        let vault_vector = table::borrow_mut(&mut registry.vaults, token_key);
        vector::push_back(vault_vector,Vault {provider: type_info::type_name<X>(),total_deposited: 0,total_borrowed: 0});
    }

    public entry fun init_vault<T>(admin: &signer, tier: u8, oracleID: u32, chain: String) acquires Permissions{
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(@dev)) {
            move_to(admin, GlobalVault {tier: tier,balance: coin::zero<T>(),});
            VerifiedTokens::allow_coin<T>(admin, tier, oracleID, chain, VerifiedTokens::give_permission(&borrow_global<Permissions>(@dev).verified_tokens));
        }
    }
    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.
    /// 
    /// Security:
    /// 1.Tato funkce muze byt zavolana pouze z smart modulu "bridge"
    /// 2.Signer musi minimalne X Qiara Tokenu stakovat
    public fun bridge_deposit<T, E, X:store>(user: &signer, permission: Permission, recipient: address,amount: u64,coins: Coin<T>, lend_rate: u64) acquires VaultRegistry, GlobalVault, Permissions {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<T>>(@dev);
        coin::merge(&mut vault.balance, coins);

        VaultTypes::change_rates<X>(lend_rate, VaultTypes::give_permission(&borrow_global<Permissions>(@dev).vault_types));
        Margin::add_deposit<T, X, Market>(recipient, amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault.total_deposited = provider_vault.total_deposited + (amount as u128);

        event::emit(BridgedDepositEvent {
            validator: signer::address_of(user),
            amount,
            from: recipient,
            token: type_info::type_name<T>(),
            chain: ChainTypes::convert_chainType_to_string<E>(),
            time: timestamp::now_seconds(),
        });}

    // T - Token From
    // Y - Token To
    // X - Vault provider From
    // Z - Vault provider To
    // A - Rewards token
    // B - Interest token
    public fun bridge_swap<T, X: store, Z:store, Y, A, B>(user: &signer, permission: Permission, recipient: address, amount_in: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit<T, X, Market>(recipient, amount_in, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_x = find_vault(borrow_global_mut<VaultRegistry>(@dev), type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault_x.total_deposited = provider_vault_x.total_deposited - (amount_in as u128);


        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Y>());

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u128) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit<Y, Z, Market>(recipient, (amount_out as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_z = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<Z>()); 
        provider_vault_z.total_deposited = provider_vault_z.total_deposited + (amount_out as u128);


        accrue<T, X, A, B>(recipient);
    }

    public entry fun swap<T, X: store, Z:store, Y, A, B>(user: &signer,amount_in: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit<T, X, Market>(signer::address_of(user), amount_in, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_x = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault_x.total_deposited = provider_vault_x.total_deposited - (amount_in as u128);


        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Y>());

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u128) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit<Y, Z, Market>(signer::address_of(user), (amount_out as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_z = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Y>(), type_info::type_name<Z>()); 
        provider_vault_z.total_deposited = provider_vault_z.total_deposited + (amount_out as u128);


        accrue<T, X, A, B>(signer::address_of(user));
    }

    public entry fun deposit<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(@dev);
        let coins = coin::withdraw<T>(user, amount);
        coin::merge(&mut vault.balance, coins);
        Margin::add_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault.total_deposited = provider_vault.total_deposited + (amount as u128);

        accrue<T,X, A, B>(signer::address_of(user));

        event::emit(VaultEvent { 
            type: utf8(b"Deposit"),
            amount, 
            address: signer::address_of(user), 
            token: type_info::type_name<T>(),
            time: timestamp::now_seconds(),
        });
    }



    /// log event emmited in this function in backend and add it to registered events in chains.move
    /// this is needed in case validators could overfetch multiple times this event and that way unlock multiple times on other chains
    /// from locked vaults
    public entry fun bridge<T, E, X:store, A, B>(user: &signer, destination_address: vector<u8>, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
       // let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);
 

        //let type_str = type_info::type_name<T>();
        //let user_vault = find_or_insert(&mut user_vault_list.list, type_str);


        withdraw<T, X, A, B>(user, amount);
        CoinTypes::deposit<T>(user, amount);
        
       // assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
       // assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

       // let coins = coin::extract(&mut vault.balance, amount);
       // coin::deposit(signer::address_of(user), coins);

       // vault.total_deposited = vault.total_deposited - amount;
       // user_vault.deposited = user_vault.deposited - amount;

       // accrue<T>(user_vault);
        event::emit(BridgeEvent { amount, validator: signer::address_of(user), token: type_info::type_name<T>(), to: destination_address, chain: ChainTypes::convert_chainType_to_string<E>(), time: timestamp::now_seconds() });
    }

    public entry fun withdraw<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(@dev);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        Margin::remove_deposit<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault.total_deposited = provider_vault.total_deposited - (amount as u128);

        accrue<T,X, A, B>(signer::address_of(user));
        event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }

    public entry fun borrow<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<T>>(@dev);

        let valueUSD = getValue(type_info::type_name<T>(), (amount as u256));
        let (depoUSD, borrowUSD, _, _, _, _) = Margin::get_user_total_usd(signer::address_of(user));

        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);
        assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        Margin::add_borrow<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault.total_borrowed = provider_vault.total_borrowed + (amount as u128);

        accrue<T, X, A, B>(signer::address_of(user));
        event::emit(VaultEvent { type: utf8(b"Borrow"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }


    public entry fun repay<T, X:store, A, B>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<T>>(@dev);

        let coins = coin::withdraw<T>(user, amount);
        coin::merge(&mut vault.balance, coins);

        Margin::remove_borrow<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<T>(), type_info::type_name<X>()); 
        provider_vault.total_borrowed = provider_vault.total_borrowed - (amount as u128);

        accrue<T, X, A, B>(signer::address_of(user));
        event::emit(VaultEvent { type: utf8(b"Repay"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }

    public entry fun claim_rewards<T, X:store, A, B>(user: &signer) acquires GlobalVault, Permissions, VaultRegistry {
        let addr = signer::address_of(user);
        let type_str = type_info::type_name<T>();

        accrue<T, X, A, B>(signer::address_of(user));
        let (rate, reward_index, interest_index, last_updated) = VaultTypes::get_vault_raw(type_info::type_name<X>());
        let (_,user_deposited, user_borrowed, user_rewards, user_interest, _) = Margin::get_user_raw_credit<T>(signer::address_of(user));

        let reward_amount = user_rewards;
        let interest_amount = user_interest;

        Margin::remove_interest<T>(signer::address_of(user), (interest_amount as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards<T>(signer::address_of(user), (reward_amount as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let global_vault = borrow_global_mut<GlobalVault<T>>(@dev);

        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(coin::value(&global_vault.balance) >= (reward as u64), ERROR_NOT_ENOUGH_LIQUIDITY);
            let coins = coin::extract(&mut global_vault.balance, (reward as u64));
            coin::deposit(addr, coins);
            event::emit(VaultEvent { type: utf8(b"Claim Rewards"), amount: (reward as u64), address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            //Margin::remove_balance<T, X, Market>(signer::address_of(user), amount, Margin::give_permission(user, &borrow_global<Permissions>(@dev).margin));
            //deposited.deposited = deposited.deposited - interest;

            event::emit(VaultEvent {  type: utf8(b"Pay Rewards"), amount: (interest as u64), address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() }); 
        }

    }

    // gets value by usd
    fun getValue(resource: String, amount: u256): u256{
        let metadata = VerifiedTokens::get_coin_metadata_by_res(resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / VerifiedTokens::get_coin_metadata_denom(&metadata)
    }

    // converts usd back to coin value
    fun getValueByCoin(resource: String, amount: u256): u256{
        let metadata = VerifiedTokens::get_coin_metadata_by_res(resource);
        //abort(100);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) / (price as u256)) / VerifiedTokens::get_coin_metadata_denom(&metadata)
    }

    #[view]
    public fun get_utilization_ratio(deposited: u128, borrowed: u128): u64 {
        //abort(147);
        if (deposited == 0 || borrowed == 0) {
            0
        } else {
            (((borrowed * 100) / deposited) as u64)
        }
    }


    #[view]
    fun get_balance_amount<T>(): u64 acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        coin::value(&vault.balance)
    }

    #[view]
    public fun get_complete_vault<T, X:store>(tokenStr: String, vaultStr: String): CompleteVault acquires GlobalVault, VaultRegistry {
        let vault = get_vaultUSD<T>(tokenStr, vaultStr);
        CompleteVault { vault: vault, coin: VerifiedTokens::get_coin_data<T>(), tier: VerifiedTokens::get_tier(vault.tier), Metadata: VerifiedTokens::get_coin_metadata<T>()  }
    }

    #[view]
    public fun get_vault(tokenStr: String, vaultStr: String): Vault acquires VaultRegistry {

        if (!table::contains(&borrow_global<VaultRegistry>(@dev).vaults, tokenStr)) {
            abort(ERROR_NO_VAULT_FOUND)
        };

        let vault_vect = table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, tokenStr);

        let i = 0;
        let len = vector::length(vault_vect);

        while (i < len) {
            let vault_ref = vector::borrow(vault_vect, i);
            if (vault_ref.provider == vaultStr) {
                // return a copy of the struct
                return Vault {provider: vault_ref.provider,total_deposited: vault_ref.total_deposited,total_borrowed: vault_ref.total_borrowed,};
            };
            i = i + 1;
        };

        abort(ERROR_NO_VAULT_FOUND)
    }

    #[view]
    public fun get_vault_raw(vaultStr: String): (String, u128, u128) acquires VaultRegistry {
        let vault_vect = table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, vaultStr);

        let i = 0;
        let len = vector::length(vault_vect);

        while (i < len) {
            let vault_ref = vector::borrow(vault_vect, i);
            if (vault_ref.provider == vaultStr) {
                return (vault_ref.provider, vault_ref.total_deposited, vault_ref.total_borrowed)
            };
            i = i + 1;
        };

        abort(ERROR_NO_VAULT_FOUND)
    }


    #[view]
    public fun get_full_vault(vaultStr: String): (vector<String>, vector<u128>, vector<u128>) acquires VaultRegistry {
        let vault_vect = table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, vaultStr);

        let i = 0;
        let len = vector::length(vault_vect);

        let providers = vector::empty<String>();
        let total_deposits = vector::empty<u128>();
        let total_borrows = vector::empty<u128>();

        while (i < len) {
            let vault_ref = vector::borrow(vault_vect, i);

            // push values into the output vectors
            vector::push_back(&mut providers, vault_ref.provider);
            vector::push_back(&mut total_deposits, vault_ref.total_deposited);
            vector::push_back(&mut total_borrows, vault_ref.total_borrowed);

            i = i + 1;
        };

        // return all vectors as tuple
        (providers, total_deposits, total_borrows)
    }



    #[view]
    public fun get_vaultUSD<T>(tokenStr: String, vaultStr: String): VaultUSD acquires GlobalVault, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        let balance = coin::value(&vault.balance);
        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());

        let vault_total = get_vault(tokenStr, vaultStr);
        let utilization = get_utilization_ratio(vault_total.total_deposited, vault_total.total_borrowed);

        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
        let (lend_apy, _, _) = QiaraMath::compute_rate((utilization as u256),(VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate(tokenStr)) as u256),((VerifiedTokens::rate_scale(VerifiedTokens::get_coin_metadata_tier(&metadata), true)) as u256),true,5);
        let (borrow_apy, _, _) = QiaraMath::compute_rate((utilization as u256),(VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate(tokenStr)) as u256),((VerifiedTokens::rate_scale(VerifiedTokens::get_coin_metadata_tier(&metadata), false)) as u256),false,5);
        VaultUSD {tier: vault.tier, oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: vault_total.total_deposited,balance: balance, borrowed: vault_total.total_borrowed, utilization: utilization, rewards: lend_apy, interest: borrow_apy, fee: get_withdraw_fee(utilization)}
    }

    #[view]
    public fun get_vault_providers(tokenStr: String): vector<Vault> acquires VaultRegistry {
        return *table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, tokenStr)
    }

    #[view]
    public fun get_withdraw_fee(utilization: u64): u64 {
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(u_bps2 > 10000){
            u_bps2 = 10000;
        };
        let bonus = ((u_bps) * 4_000) / (20000 - u_bps2);
        return (bonus)
    }

    fun tttta(number: u64){
        abort(number);
    }


    public fun accrue<T, X: store, A, B>(user: address) acquires GlobalVault, Permissions, VaultRegistry {
       // tttta(1);
        // staci fetchovat jen jeden vault teoreticky? protoze z nej poterbuju ty rewards a interests indexy? a to pak previst na token A a B... ?
        let (lend_rate, reward_index, interest_index, last_updated) = VaultTypes::get_vault_raw(type_info::type_name<T>()); // CHECK
        //tttta(2);
        let vault = get_vault(type_info::type_name<T>(), type_info::type_name<X>()); // CHECK
        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());
        let utilization = get_utilization_ratio(vault.total_deposited, vault.total_borrowed);
        VaultTypes::accrue_global<T>((lend_rate as u256), (VerifiedTokens::rate_scale((VerifiedTokens::get_coin_metadata_tier(&metadata)), false) as u256), (utilization as u256), (get_balance_amount<T>() as u256), (((get_balance_amount<T>() as u128) - vault.total_deposited) as u256), VaultTypes::give_permission(&borrow_global<Permissions>(@dev).vault_types));
        //tttta(3);
        let scale: u128 = 1000000000000000000;
        //ttta(7012);
        let (_,_, _, user_reward_index, user_interest_index, _) = Margin::get_user_raw_balance<T, X, Market>(user); // CHECK
        //tttta(7);
        let (_,user_deposited, user_borrowed, user_rewards, user_interest, _) = Margin::get_user_raw_credit<T>(user);  // CHECK
        //tttta(10);
        // Apply rewards based on reward index delta
        let delta_reward = reward_index - (user_reward_index as u128);
        let user_delta_reward_value  = ((((user_deposited as u128) * delta_reward) / scale) as u256);
        let receive_rewards_in_A_tokens = getValueByCoin(type_info::type_name<B>(), getValue(type_info::type_name<T>(), user_delta_reward_value));
        //tttta(3);
        Margin::add_rewards<A>(user, (receive_rewards_in_A_tokens as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::update_reward_index<T, X, Market>(user, reward_index, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        // Apply interest based on interest index delta
        let delta_interest = interest_index - (user_interest_index as u128);
        let user_delta_interest_value = ((((user_borrowed as u128) * delta_interest) / scale) as u256);
        let pay_interest_in_B_tokens = getValueByCoin(type_info::type_name<A>(), getValue(type_info::type_name<T>(), user_delta_interest_value));
        Margin::add_interest<B>(user, (pay_interest_in_B_tokens as u64) , Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::update_interest_index<T, X, Market>(user, interest_index, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        Margin::update_time<T, X, Market>(user, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
    }

fun find_vault(vault_table: &mut VaultRegistry, token: String, provider: String): &mut Vault {
    // borrow the vector mutably from the table
   // abort(ERROR_NO_VAULT_FOUND);
    if (!table::contains(&vault_table.vaults, token)) {
        abort(ERROR_NO_VAULT_FOUND)
    };

    let vault_vect = table::borrow_mut(&mut vault_table.vaults, token);

    let i = 0;
    let len = vector::length(vault_vect);

    while (i < len) {
        let vault_ref = vector::borrow_mut(vault_vect, i);
        if (vault_ref.provider == provider) {
            return vault_ref;
        };
        i = i + 1;
    };

    abort(ERROR_NO_VAULT_FOUND_FULL_CYCLE)
}

}