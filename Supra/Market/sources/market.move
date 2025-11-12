module dev::QiaraVaultsV35 {
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

    use dev::QiaraVerifiedTokensV41::{Self as VerifiedTokens, Tier, CoinData, VMetadata, Access as VerifiedTokensAccess};
    use dev::QiaraMarginV44::{Self as Margin, Access as MarginAccess};

    use dev::QiaraFeeVaultV7::{Self as fee};

    use dev::QiaraCoinTypesV11::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use dev::QiaraChainTypesV11::{Self as ChainTypes};
    use dev::QiaraVaultRatesV11::{Self as VaultRates, Access as VaultRatesAccess};
    use dev::QiaraFeatureTypesV11::{Market};

    use dev::QiaraMathV9::{Self as QiaraMath};

    use dev::QiaraStorageV30::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV30::{Self as capabilities, Access as CapabilitiesAccess};


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
        vault_rates: VaultRatesAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
        verified_tokens: VerifiedTokensAccess,
    }

// === STRUCTS === //
   
   // Maybe in the future remove this, and move total borrowed into global vault? idk tho how would it do because of the phantom type tag
    struct Vault has key, store, copy, drop{
        token: String,
        total_deposited: u256,
        total_borrowed: u256,
        locked: u256,
    }


    struct FullVault has key, store, copy, drop{
        token: String,
        total_deposited: u256,
        total_borrowed: u256,
        utilization: u64,
        lend_rate: u64,
        borrow_rate: u64
    }


    struct VaultRegistry has key {
        vaults: table::Table<String, Vault>,
    }

    struct GlobalVault<phantom T> has key {
        balance: coin::Coin<T>,
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
        coin: CoinData,
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
    fun init_module(admin: &signer) acquires VaultRegistry{
        if (!exists<VaultRegistry>(@dev)) {
            move_to(admin, VaultRegistry {vaults: table::new<String, Vault>()});
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), vault_rates:  VaultRates::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin), verified_tokens:  VerifiedTokens::give_access(admin)});
        };
        init_all_vaults(admin);

    }

    public fun init_all_vaults(address: &signer) acquires VaultRegistry{
        init_vault<BaseEthereum>(address);
        init_vault<BaseUSDC>(address);

        init_vault<SuiEthereum>(address);
        init_vault<SuiUSDC>(address);
        init_vault<SuiUSDT>(address);
        init_vault<SuiSui>(address);
        init_vault<SuiBitcoin>(address);

        init_vault<SupraCoin>(address);
    }

    public entry fun init_vault<T>(admin: &signer) acquires VaultRegistry{
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(@dev)) {
            move_to(admin, GlobalVault {balance: coin::zero<T>()});
        };
        let registry = borrow_global_mut<VaultRegistry>(@dev);
            table::add(
                &mut registry.vaults,
                type_info::type_name<T>(),
                Vault {token: type_info::type_name<T>() , total_deposited:0, total_borrowed:0, locked: 0},
            );
    }
    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.
    /// 
    /// Security:
    /// 1.Tato funkce muze byt zavolana pouze z smart modulu "bridge"
    /// 2.Signer musi minimalne X Qiara Tokenu stakovat
    public fun bridge_deposit<Token, Chain>(user: &signer, permission: Permission, recipient: address,amount: u64,coins: Coin<Token>, lend_rate: u64) acquires VaultRegistry, GlobalVault, Permissions {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<Token>>(@dev);
        coin::merge(&mut vault.balance, coins);

        VaultRates::change_rates<Token>(lend_rate, VaultRates::give_permission(&borrow_global<Permissions>(@dev).vault_rates));
        Margin::add_deposit<Token, Market>(recipient, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev), type_info::type_name<Token>()); 
        provider_vault.total_deposited = provider_vault.total_deposited + (amount as u256);

        event::emit(BridgedDepositEvent {
            validator: signer::address_of(user),
            amount,
            from: recipient,
            token: type_info::type_name<Token>(),
            chain: ChainTypes::convert_chainType_to_string<Chain>(),
            time: timestamp::now_seconds(),
        });}

    // T - Token From
    // Y - Token To
    // X - Vault provider From
    // Z - Vault provider To
    // A - Rewards token
    // B - Interest token
    public fun bridge_swap<Token, TokenTo, TokenReward, TokenInterest>(user: &signer, permission: Permission, recipient: address, amount_in: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit<Token, Market>(recipient, (amount_in as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_from = find_vault(borrow_global_mut<VaultRegistry>(@dev), type_info::type_name<Token>()); 
        provider_vault_from.total_deposited = provider_vault_from.total_deposited - (amount_in as u256);


        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Token>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<TokenTo>());

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u256) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit<TokenTo, Market>(recipient, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_to = find_vault(borrow_global_mut<VaultRegistry>(@dev), type_info::type_name<TokenTo>()); 
        provider_vault_to.total_deposited = provider_vault_to.total_deposited + (amount_out as u256);


        accrue<Token, TokenReward, TokenInterest>(recipient);
    }

    public entry fun swap<Token, TokenTo, TokenReward, TokenInterest>(user: &signer,amount_in: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit<Token, Market>(signer::address_of(user), (amount_in as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_from = find_vault(borrow_global_mut<VaultRegistry>(@dev), type_info::type_name<Token>()); 
        provider_vault_from.total_deposited = provider_vault_from.total_deposited - (amount_in as u256);


        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Token>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<TokenTo>());

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u256) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit<Token, Market>(signer::address_of(user), (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault_to = find_vault(borrow_global_mut<VaultRegistry>(@dev), type_info::type_name<TokenTo>()); 
        provider_vault_to.total_deposited = provider_vault_to.total_deposited + (amount_out as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
    }

    public entry fun deposit<Token, TokenReward, TokenInterest>(user: &signer, amount: u64, rate: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<Token>>(@dev);
        let coins = coin::withdraw<Token>(user, amount);
        coin::merge(&mut vault.balance, coins);
        Margin::add_deposit<Token, Market>(signer::address_of(user), (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Token>()); 
        provider_vault.total_deposited = provider_vault.total_deposited + (amount as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
        VaultRates::change_rates<Token>(rate, VaultRates::give_permission(&borrow_global<Permissions>(@dev).vault_rates));
        event::emit(VaultEvent { 
            type: utf8(b"Deposit"),
            amount, 
            address: signer::address_of(user), 
            token: type_info::type_name<Token>(),
            time: timestamp::now_seconds(),
        });
    }


    // lock margined $ value
    public entry fun lock<Token, TokenReward, TokenInterest>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<Token>>(@dev);

        Margin::add_lock<Token, Market>(signer::address_of(user), (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let (_, _, marginUSD, _, _, _, _, _, _) = Margin::get_user_total_usd(signer::address_of(user));

        assert!(marginUSD >= (amount as u256), ERROR_NOT_ENOUGH_MARGIN);

        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Token>()); 
        provider_vault.locked = provider_vault.locked + (amount as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
        event::emit(VaultEvent { 
            type: utf8(b"Lock"),
            amount, 
            address: signer::address_of(user), 
            token: type_info::type_name<Token>(),
            time: timestamp::now_seconds(),
        });
    }

    public entry fun unlock<Token, TokenReward, TokenInterest>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Token>()); 

        assert!(provider_vault.locked - (amount as u256) <= provider_vault.locked, ERROR_UNLOCK_BIGGER_THAN_LOCK);

        provider_vault.locked = provider_vault.locked - (amount as u256);
        Margin::remove_lock<Token, Market>(signer::address_of(user), (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
        event::emit(VaultEvent { 
            type: utf8(b"Unlock"),
            amount, 
            address: signer::address_of(user), 
            token: type_info::type_name<Token>(),
            time: timestamp::now_seconds(),
        });
    }

    /// log event emmited in this function in backend and add it to registered events in chains.move
    /// this is needed in case validators could overfetch multiple times this event and that way unlock multiple times on other chains
    /// from locked vaults
    public entry fun bridge<Token: store, Chain, TokenReward, TokenInterest>(user: &signer, destination_address: vector<u8>, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
       // let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);
 

        //let type_str = type_info::type_name<T>();
        //let user_vault = find_or_insert(&mut user_vault_list.list, type_str);


        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
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

    public entry fun withdraw<Token, TokenReward, TokenInterest>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<Token>>(@dev);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        //100 000 000 = 1 size
        // 1000 * 100 000 000 = 100 000 000 000
        // 1000 * 100 000 000 = 100 000 000 000
        // 0.01% fee
        // 1000
        let fee_amount = VerifiedTokens::get_coin_metadata_market_w_fee(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Token>())) * (amount as u64) / 1000000;
        fee::pay_fee<Token>(user, coin::withdraw<Token>(user, fee_amount), utf8(b"Withdraw Fee"));

        Margin::remove_deposit<Token, Market>(signer::address_of(user), (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Token>()); 
        provider_vault.total_deposited = provider_vault.total_deposited - (amount as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
        event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }

    public entry fun borrow<Token, TokenReward, TokenInterest>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<Token>>(@dev);

        let valueUSD = getValue(type_info::type_name<Token>(), (amount as u256));
        let (depoUSD, _, _, borrowUSD, _, _, _, _, _) = Margin::get_user_total_usd(signer::address_of(user));

        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);
        assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        Margin::add_borrow<Token, Market>(signer::address_of(user), (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Token>()); 
        provider_vault.total_borrowed = provider_vault.total_borrowed + (amount as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
        event::emit(VaultEvent { type: utf8(b"Borrow"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }


    public entry fun repay<Token, TokenReward, TokenInterest>(user: &signer, amount: u64) acquires GlobalVault, Permissions, VaultRegistry {
        assert!(exists<GlobalVault<Token>>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<Token>>(@dev);

        let coins = coin::withdraw<Token>(user, amount);
        coin::merge(&mut vault.balance, coins);

        Margin::remove_borrow<Token, Market>(signer::address_of(user), (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        let provider_vault = find_vault(borrow_global_mut<VaultRegistry>(@dev),  type_info::type_name<Token>()); 
        provider_vault.total_borrowed = provider_vault.total_borrowed - (amount as u256);

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
        event::emit(VaultEvent { type: utf8(b"Repay"), amount, address: signer::address_of(user), token: type_info::type_name<Token>(), time: timestamp::now_seconds() });
    }

    public entry fun claim_rewards<Token, TokenReward, TokenInterest>(user: &signer) acquires GlobalVault, Permissions, VaultRegistry {
        let addr = signer::address_of(user);
        let type_str = type_info::type_name<Token>();

        accrue<Token, TokenReward, TokenInterest>(signer::address_of(user));
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

    }

    // gets value by usd
    #[view]
    public fun getValue(resource: String, amount: u256): u256{
        let metadata = VerifiedTokens::get_coin_metadata_by_res(resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracleID(&metadata));
       // let denom = pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / VerifiedTokens::get_coin_metadata_denom(&metadata)
    }

    // converts usd back to coin value
    #[view]
    public fun getValueByCoin(resource: String, amount: u256): u256{
        let metadata = VerifiedTokens::get_coin_metadata_by_res(resource);
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
    public fun get_balance_amount<T>(): u64 acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        coin::value(&vault.balance)
    }

    #[view]
    public fun get_complete_vault<T, X:store>(tokenStr: String,): CompleteVault acquires GlobalVault, VaultRegistry {
        let vault = get_vaultUSD<T>(tokenStr);
        let metadata = VerifiedTokens::get_coin_metadata_by_res(tokenStr);
        CompleteVault { vault: vault, coin: VerifiedTokens::get_coin_data<T>(), w_fee: VerifiedTokens::get_coin_metadata_market_w_fee(&metadata), Metadata: metadata  }
    }

    #[view]
    public fun get_vault(tokenStr: String): Vault acquires VaultRegistry {

        if (!table::contains(&borrow_global<VaultRegistry>(@dev).vaults, tokenStr)) {
            abort(ERROR_NO_VAULT_FOUND)
        };

        *find_vault(borrow_global_mut<VaultRegistry>(@dev), tokenStr)
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
        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());

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
    }


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


    public fun accrue<Token, TokenReward, TokenInterest>(user: address) acquires GlobalVault, Permissions, VaultRegistry {
        // staci fetchovat jen jeden vault teoreticky? protoze z nej poterbuju ty rewards a interests indexy? a to pak previst na token A a B... ?
        let (lend_rate, reward_index, interest_index, last_updated) = VaultRates::get_vault_raw(type_info::type_name<Token>()); // CHECK
        let vault = get_vault(type_info::type_name<Token>()); // CHECK
      //  tttta((lend_rate as u64));
        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Token>());
        //tttta((lend_rate as u64)); // 0x9863
        let utilization = get_utilization_ratio(vault.total_deposited, vault.total_borrowed);
        //tttta((utilization as u64)); // 0x0
        //tttta((lend_rate as u64)); // 0x1035a 66394
        //tttta((VerifiedTokens::rate_scale((VerifiedTokens::get_coin_metadata_tier(&metadata)), false) as u64)); // 0xdac 3500
        //tttta( (get_balance_amount<T>() as u64)); // 0xe8d4a50e0b 100000000011 999999999999 0xe8d4a44caf 999999949999
        //tttta(((vault.total_deposited) as u64)); // 0xe8d4a50fff 1000000004095 999999999999 0xe8d4a50fff 999999999999
        VaultRates::accrue_global<Token>((lend_rate as u256), (VerifiedTokens::get_coin_metadata_rate_scale((&metadata), false) as u256), (utilization as u256), (get_balance_amount<Token>() as u256), (vault.total_borrowed as u256), VaultRates::give_permission(&borrow_global<Permissions>(@dev).vault_rates));
        //tttta((utilization as u64));
        let scale: u128 = 1_000_000;
        let (_,user_deposited, user_borrowed, user_rewards,user_reward_index, user_interest, user_interest_index, _) = Margin::get_user_raw_balance<Token, Market>(user); // CHECK

        // 11700
        // 237405 - 147238 = 90167
        if ((reward_index) > (user_reward_index as u128)) {
            let delta_reward = reward_index - (user_reward_index as u128);
            //tttta((user_reward_index as u64));
            if((((user_deposited as u128) * delta_reward) / scale) > 0){
                let user_delta_reward_value  = ((((user_deposited as u128) * delta_reward) / scale) as u256);
                let receive_rewards_in_A_tokens = getValueByCoin(type_info::type_name<TokenReward>(), getValue(type_info::type_name<Token>(), user_delta_reward_value));
                Margin::add_rewards<TokenReward, Market>(user, (receive_rewards_in_A_tokens as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_reward_index<TokenReward, Market>(user, (reward_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_time<TokenReward, Market>(user, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
        };

        if ((interest_index) > (user_interest_index as u128)) {
           // tttta((user_interest_index as u64));
            let delta_interest = interest_index - (user_interest_index as u128);
            if((((user_borrowed as u128) * delta_interest) / scale) > 0){
                let user_delta_interest_value = ((((user_borrowed as u128) * delta_interest) / scale) as u256);
                //tttta((user_borrowed as u64));
                let pay_interest_in_B_tokens = getValueByCoin(type_info::type_name<TokenInterest>(), getValue(type_info::type_name<Token>(), user_delta_interest_value));
                Margin::add_interest<TokenInterest, Market>(user, (pay_interest_in_B_tokens as u256) , Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_interest_index<TokenInterest, Market>(user, (interest_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_time<TokenInterest, Market>(user, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
        }; 
    }

    fun find_vault(vault_table: &mut VaultRegistry, token: String): &mut Vault {
        if (!table::contains(&vault_table.vaults, token)) {
            abort ERROR_NO_VAULT_FOUND;
        };

        table::borrow_mut(&mut vault_table.vaults, token)
    }
}
