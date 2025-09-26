module dev::QiaraVaultsV1 {
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

    use dev::AexisVaultFactoryV18::{Self as Factory, Tier, CoinData, Metadata};
    use dev::QiaraTokenStorageV18::{Self as TokenStorage, Access as TokenStorageAccess};
    use dev::QiaraMath::{Self as Math};

    use dev::AexisCoinTypesV2::{Self as CoinDeployer, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use dev::AexisChainTypesV2::{Self as ChainTypes};
    use dev::AexisVaultProviderTypesV2::{Self as VaultProviders};

    use dev::QiaraStorageV20::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV20::{Self as capabilities, Access as CapabilitiesAccess};

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

    const ADMIN: address = @dev;

    const SECONDS_IN_YEAR: u64 = 31_536_000; // 365 days

    const MAX_COLLATERAL_RATIO: u64 = 80; // Safe borrowing limit (%)
    const LIQUIDATION_THRESHOLD: u64 = 85; // Liquidation trigger (%)
    const LIQUIDATION_BONUS_BPS: u64 = 500; // 5% bonus to liquidator

    struct Permissions has key, store, drop {
        token_storage_access: TokenStorageAccess,
    }

    struct RateList has key {
        rates: table::Table<String, Rates>, 
    }

    // Wrapper to store heterogeneous entries
    struct Rates has copy, drop, store {
        lend_rate: u64,
        borrow_rate: u64,
    }

    struct TableUnclaimedUserVaultList has key {
        list: table::Table<address, table::Table<String, vector<PendingDeposit>>>,
    }

    struct PendingDeposit has copy, key, store {
        resource: String,
        deposited: u64,
    }

    struct UserVaultRegistry has key, store {
        coins: vector<String>,
    }

// deposited:  table::Table<CoinType, table::Table<VaultProviderType, Deposited>, 
    struct UserVault has store, key {
        deposited:  table::Table<String, vector<Deposited>>, 
    }

    struct Deposited has copy, key, store, drop {
        resource: String,
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
        last_update: u64,
        penalty: u64,
    }


    struct GlobalVault<phantom T> has key {
        tier: u8,
        total_deposited: u64,
        balance: coin::Coin<T>,
        external_rewards: u64,
        external_interest: u64,
    }

    struct VaultUSD has store, copy, drop {
        tier: u8,
        oracle_price: u128,
        oracle_decimals: u8,
        total_deposited: u64,
        balance: u64,
        borrowed: u64,
        utilization: u64,
        rewards: u64,
        interest: u64,
        external_rewards: u64,
        external_interest: u64,
        fee: u64,
    }


    struct CompleteVault has key{
        vault: VaultUSD,
        coin: CoinData,
        tier: Tier,
        Metadata: Metadata,
    }

    struct Access has store, key, drop {}

    struct UserCap has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == ADMIN, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_usercap(s: &signer, access: &Access): UserCap {
        // access is consumed automatically
        UserCap {}
    }

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

    #[event]
    struct LiquidationEvent has copy, drop, store {
        borrower: address,
        liquidator: address,
        repaid: u64,
        collateral_seized: u64,
        token: String,
        time: u64
    }

    fun get_admin(): address {
        ADMIN
    }

    public entry fun init_all_vaults(address: &signer){
        init_vault<BaseEthereum>(address, 1, 1, utf8(b"Base"));
        init_vault<BaseUSDC>(address, 0, 47,  utf8(b"Base"));

        init_vault<SuiEthereum>(address, 1, 1,  utf8(b"Sui"));
        init_vault<SuiUSDC>(address, 0, 47, utf8(b"Sui"));
        init_vault<SuiUSDT>(address, 0, 47, utf8(b"Sui"));
        init_vault<SuiSui>(address, 2, 90, utf8(b"Sui"));
        init_vault<SuiBitcoin>(address, 1, 0, utf8(b"Sui"));

        init_vault<SupraCoin>(address, 3, 500, utf8(b"Supra"));
    }

    fun init_module(address: &signer){
        move_to(address, TableUnclaimedUserVaultList {list: table::new<address, table::Table<String, vector<PendingDeposit>>>(),});
        move_to(address, RateList {rates: table::new<String, Rates>()});
        init_all_vaults(address)
    }

    public entry fun init_vault<T>(admin: &signer, tier: u8, oracleID: u32, chain: String){
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(ADMIN)) {
            //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
            let type = type_info::type_name<T>();
            move_to(admin, GlobalVault {
                tier: tier,
                total_deposited: 0,
                balance: coin::zero<T>(),
                external_rewards: 0,
                external_interest: 0,
            });
            Factory::allow_coin<T>(admin, tier, oracleID, chain);
        }
    }

    public entry fun init_user_vault(user: &signer) {
        let addr = signer::address_of(user);
        if (!exists<UserVaultRegistry>(addr)) {
            move_to(user, UserVaultRegistry { coins: vector::empty<String>()});
        };
        if (!exists<UserVault>(addr)) {
            move_to(user, UserVault { deposited: table::new<String, vector<Deposited>>()});
        };
    }

    public entry fun claim_bridged_deposits<T, X>(user: &signer) acquires UserVault, TableUnclaimedUserVaultList, UserVaultRegistry {
        let tbl = borrow_global_mut<TableUnclaimedUserVaultList>(ADMIN);

        assert!(exists<UserVault>(signer::address_of(user)), ERROR_USER_VAULT_NOT_INITIALIZED);
        let type_str = type_info::type_name<T>();
        insert_vault_registry(type_str, type_info::type_name<X>());

        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));
        let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());

        let pending_list = table::borrow_mut(&mut tbl.list, signer::address_of(user));
        let coin_pending_list = table::borrow_mut(pending_list, type_str);
        let pending_deposit_by_vault_provider = find_pending_deposit(coin_pending_list, type_info::type_name<X>());

        let amount = pending_deposit_by_vault_provider.deposited;
        pending_deposit_by_vault_provider.deposited = 0;
        deposited.deposited = deposited.deposited + amount;
    }

    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.
    public fun bridge_deposit<T, E, X:store>(user: &signer,_access: &Access,_user_cap: UserCap,recipient: address,amount: u64,coins: Coin<T>, lend_rate: u64, borrow_rate: u64) acquires GlobalVault, UserVault, RateList, UserVaultRegistry, TableUnclaimedUserVaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);

        // Deposit coins into the global vault balance
        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);
        coin::merge(&mut vault.balance, coins);
        vault.total_deposited = vault.total_deposited + amount;

        let type_str = type_info::type_name<T>();
        insert_vault_registry(type_str, type_info::type_name<X>());

        change_rates<X>(lend_rate, borrow_rate);
        if (exists<UserVault>(recipient)) {
            //  Recipient already has a vault list
            let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));
            let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());
            deposited.deposited = deposited.deposited + amount;
            accrue<T, X>(deposited);
        } else {
            //  Recipient has no vault list yet  store in unclaimed table
            let tbl = borrow_global_mut<TableUnclaimedUserVaultList>(ADMIN);

            if (!table::contains(&tbl.list, recipient)) {
                let inner_table = table::new<String, vector<PendingDeposit>>();
                table::add(&mut tbl.list, recipient, inner_table);
            };

            let pending_list = table::borrow_mut(&mut tbl.list, recipient);
            let coin_pending_list = table::borrow_mut(pending_list, type_str);
            let pending_deposit_by_vault_provider = find_pending_deposit(coin_pending_list, type_info::type_name<X>());

            pending_deposit_by_vault_provider.deposited = pending_deposit_by_vault_provider.deposited + amount;

        };

        // Emit deposit event
        event::emit(BridgedDepositEvent {
            validator: signer::address_of(user),
            amount,
            from: recipient,
            token: type_str,
            chain: ChainTypes::convert_chainType_to_string<E>(),
            time: timestamp::now_seconds(),
        });}


    public entry fun deposit<T, X:store>(user: &signer, amount: u64) acquires GlobalVault,  UserVault, UserVaultRegistry, RateList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let type_str = type_info::type_name<T>();
        insert_vault_registry(type_str, type_info::type_name<X>());

        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));
        let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());

        let coins = coin::withdraw<T>(user, amount);
        coin::merge(&mut vault.balance, coins);

        vault.total_deposited = vault.total_deposited + amount;
        deposited.deposited = deposited.deposited + amount;

        accrue<T,X>(deposited);

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
    public entry fun bridge<T, E, X:store>(user: &signer, destination_address: vector<u8>, amount: u64) acquires GlobalVault, UserVault, RateList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
       // let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);
 

        //let type_str = type_info::type_name<T>();
        //let user_vault = find_or_insert(&mut user_vault_list.list, type_str);


        withdraw<T, X>(user, amount);
        CoinDeployer::deposit<T>(user, amount);
        
       // assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
       // assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

       // let coins = coin::extract(&mut vault.balance, amount);
       // coin::deposit(signer::address_of(user), coins);

       // vault.total_deposited = vault.total_deposited - amount;
       // user_vault.deposited = user_vault.deposited - amount;

       // accrue<T>(user_vault);
        event::emit(BridgeEvent { amount, validator: signer::address_of(user), token: type_info::type_name<T>(), to: destination_address, chain: ChainTypes::convert_chainType_to_string<E>(), time: timestamp::now_seconds() });
    }

    public entry fun withdraw<T, X:store>(user: &signer, amount: u64) acquires GlobalVault, UserVault, RateList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));
        let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());

        assert!(deposited.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        vault.total_deposited = vault.total_deposited - amount;
        deposited.deposited = deposited.deposited - amount;

        accrue<T,X>(deposited);
        event::emit(VaultEvent { type: utf8(b"Withdraw"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }

    public entry fun borrow<T, X:store>(user: &signer, amount: u64) acquires GlobalVault, UserVault, UserVaultRegistry, RateList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);

        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let valueUSD = getValue(type_info::type_name<T>(), (amount as u256));
        let (depoUSD, borrowUSD, _, _) = get_user_total_usd(signer::address_of(user));

        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));
        let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());

        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);
        assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        deposited.borrowed = deposited.borrowed + amount;
        accrue<T, X>(deposited);
        event::emit(VaultEvent { type: utf8(b"Borrow"), amount, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
    }

    public entry fun claim_rewards<T, X:store>(user: &signer) acquires GlobalVault, UserVault, RateList {
        let addr = signer::address_of(user);

        let type_str = type_info::type_name<T>();
        let user_vault = borrow_global_mut<UserVault>(addr);
        let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());

        accrue<T, X>(deposited);

        let reward_amount = deposited.rewards;
        let interest_amount = deposited.interest;
        deposited.interest = 0;
        deposited.rewards = 0;
        let global_vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        
        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(coin::value(&global_vault.balance) >= reward, ERROR_NOT_ENOUGH_LIQUIDITY);
            let coins = coin::extract(&mut global_vault.balance, reward);
            coin::deposit(addr, coins);
            event::emit(VaultEvent { type: utf8(b"Claim Rewards"), amount: reward, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            deposited.deposited = deposited.deposited - interest;

            event::emit(VaultEvent {  type: utf8(b"Pay Rewards"), amount: interest, address: signer::address_of(user), token: type_info::type_name<T>(), time: timestamp::now_seconds() }); 
        }

    }

    public entry fun liquidate<T, X: store>(liquidator: &signer, borrower_addr: address) acquires GlobalVault, UserVault, UserVaultRegistry, RateList {

        let type_str = type_info::type_name<T>();

        let (depoUSD, borrowUSD, _, _) = get_user_total_usd(borrower_addr);

        assert!(depoUSD < borrowUSD, ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION);

        let repayUSD = borrowUSD - depoUSD;
        let repayCoin = getValueByCoin(type_str, repayUSD);

        let user_vault = find_user_deposited(borrow_global_mut<UserVault>(borrower_addr), type_info::type_name<T>(), type_info::type_name<X>());

        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);

        accrue<T, X>(user_vault);
        let global_vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        // bonus = 5% of repay
        let bonus = (repayCoin * (LIQUIDATION_BONUS_BPS as u256)) / 10000;
        let total_deduction = repayCoin + bonus;

        // deduct from borrower
        if(user_vault.deposited <= (total_deduction as u64)){
            user_vault.deposited = 0;
        } else {
            user_vault.deposited = user_vault.deposited - (total_deduction as u64);
        };

        // bonus goes to liquidator
        let collateral_bonus = coin::extract(&mut global_vault.balance, (bonus as u64));
        coin::deposit(signer::address_of(liquidator), collateral_bonus);

        // record penalty for borrower
        //user_vault_x.liquidated = user_vault_x.liquidated + (total_deduction as u64);

        event::emit(LiquidationEvent {
            borrower: borrower_addr,
            liquidator: signer::address_of(liquidator),
            repaid: (repayCoin as u64),
            collateral_seized: (bonus as u64),
            token: type_info::type_name<T>(),
            time: timestamp::now_seconds(),
        });
    }

    fun change_rates<X>(lend_rate: u64, borrow_rate: u64) acquires RateList {
        let x = borrow_global_mut<RateList>(@dev);
        let key = type_info::type_name<X>();

        if (!table::contains(&x.rates, key)) {
            table::add(&mut x.rates, key, Rates { lend_rate, borrow_rate });
        } else {
            let rate = table::borrow_mut(&mut x.rates, key);
            rate.lend_rate = lend_rate;
            rate.borrow_rate = borrow_rate;
        }
    }


    fun get_apy<T, X:store>(vault: &GlobalVault<T>): u64 acquires RateList{
        
        let bonus_apy = get_lend_rate<X>();

        let utilization = get_utilization_ratio<T>(vault); // in %
        let tier = Factory::get_tier(vault.tier);
        let minimum_apr = Factory::apr_increase(vault.tier);
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(utilization > 110){
            u_bps2 = 10_999;
        };
        return ((((u_bps) * 2_000) / (11_000 - u_bps2) + (minimum_apr as u64))) + bonus_apy
    }

    fun get_interest<T, X: store>(vault: &GlobalVault<T>): u64 acquires RateList{

        let bonus_interest = get_borrow_rate<X>();

        let utilization = get_utilization_ratio<T>(vault); // in %
        let tier = Factory::get_tier(vault.tier);
        let minimum_apr = Factory::apr_increase(vault.tier);
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(utilization > 110){
            u_bps2 = 7499;
        };
        return ((((u_bps) * 3_000) / (7500 - u_bps2) + (minimum_apr as u64)*2)) + bonus_interest
    }

    fun getValue(resource: String, amount: u256): u256{
        let metadata = Factory::get_coin_metadata_by_res(&resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        let denom = pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / denom
    }

    fun getValueByCoin(resource: String, amount: u256): u256{
        let metadata = Factory::get_coin_metadata_by_res(&resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        let denom = pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) / (price as u256)) / denom
    }

    fun get_utilization_ratio<T>(vault: &GlobalVault<T>): u64 {
        let borrowed = vault.total_deposited - coin::value(&vault.balance);
        if (vault.total_deposited == 0) {
            0
        } else {
            (borrowed * 100) / vault.total_deposited
        }
    }


    #[view]
    public fun get_complete_vault<T, X:store>(): CompleteVault acquires GlobalVault, RateList {
        let vault = get_vault<T, X>();
        CompleteVault { vault: vault, coin: Factory::get_coin_data<T>(), tier: Factory::get_tier(vault.tier), Metadata: Factory::get_coin_metadata<T>()  }
    }

    #[view]
    public fun get_vault<T, X: store>(): VaultUSD acquires GlobalVault, RateList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let balance = coin::value(&vault.balance);
        let metadata = Factory::get_coin_metadata_by_res(&type_info::type_name<T>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        let denom = pow10_u256((price_decimals as u8));
        VaultUSD {tier: vault.tier, oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: vault.total_deposited,balance,borrowed: vault.total_deposited - balance, utilization:  get_utilization_ratio<T>(vault), rewards: get_apy<T, X>(vault), interest: get_interest<T, X>(vault), external_interest: get_borrow_rate<X>(),  external_rewards: get_lend_rate<X>(), fee: get_withdraw_fee(get_utilization_ratio<T>(vault))}
    }

    #[view]
    public fun get_user_vault<T, X>(addr: address): Deposited acquires UserVault {
        assert!(exists<UserVault>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);

        let vault = borrow_global<UserVault>(addr);
        let deposits = table::borrow(&vault.deposited, type_info::type_name<T>());

        let len = vector::length(deposits);
        while (len > 0) {
            let deposit = vector::borrow(deposits, len - 1);
            if (deposit.resource == type_info::type_name<X>()) {
                return *deposit;
            };
            len = len - 1;
        };

        abort ERROR_VAULT_NOT_INITIALIZED
    }


    #[view]
    public fun get_user_vaults<T>(addr: address): vector<Deposited> acquires UserVault {
        assert!(exists<UserVault>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<UserVault>(addr);
        *table::borrow(&vault.deposited, type_info::type_name<T>())
    }

    #[view]
    public fun get_user_collatelar_ratio<T,X>(address: address): u64  acquires UserVault{
        let vault = get_user_vault<T,X>(address);
        (vault.borrowed * 100) / vault.deposited
    }

    #[view]
    public fun get_user_position_usd<T,X>(addr: address): (u256, u256, u256, u256) acquires UserVault {
        let uv = get_user_vault<T,X>(addr);

        // get coin decimals
        let coin_decimals = coin::decimals<T>();

        // lookup oracle metadata
        let metadata = Factory::get_coin_metadata_by_res(&type_info::type_name<T>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        
        // normalize amount * price / 10^coin_decimals
        let denom = pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

        let dep_usd = ((((uv.deposited as u256) * (price as u256)) / denom)*(Factory::lend_ratio(Factory::get_coin_metadata_tier(&metadata)) as u256))/100;
        let bor_usd = ((uv.borrowed as u256)  * (price as u256)) / denom;
        let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
        let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

        (dep_usd, bor_usd, reward_usd ,interest_usd)
    }

    #[view]
    public fun get_user_total_usd(addr: address): (u256, u256, u256, u256) acquires UserVaultRegistry, UserVault{
        let user_vault = borrow_global_mut<UserVault>(addr);
        let user_vault_registry = borrow_global_mut<UserVaultRegistry>(addr);

        let total_dep = 0u256;
        let total_bor = 0u256;
        let total_rew = 0u256;
        let total_int = 0u256;

        let n = vector::length(&user_vault_registry.coins);
        let i = 0;
        while (i < n) {
            let key_vault_type = vector::borrow(&user_vault_registry.coins, i);
            let provider_list = VaultProviders::return_all_vault_provider_types();
            let x = vector::length(&user_vault_registry.coins);
            let y = 0;
            while (y < x) {
                let provider = vector::borrow(&provider_list, x);
                let uv = find_user_deposited(user_vault, *key_vault_type, *provider);            
                let metadata = Factory::get_coin_metadata_by_res(&uv.resource);
                let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));


                // denominator = 10^(coin_decimals + price_decimals)
                let denom = pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

                // deposited/borrowed value in USD
                let dep_usd = ((uv.deposited as u256) * (price as u256)) / denom;
                let bor_usd = ((uv.borrowed  as u256) * (price as u256)) / denom;
                let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
                let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

                // apply lend rate (assumed %)
                total_dep = total_dep + (dep_usd * (Factory::lend_ratio(Factory::get_coin_metadata_tier(&metadata)) as u256))/100;
                total_bor = total_bor + bor_usd;
                total_rew = total_rew + reward_usd;
                total_int = total_int + interest_usd;

                x = x + 1;
            };

            i = i + 1;
        };
        (total_dep, total_bor, total_rew, total_int)
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

    // JUST A HELP FUNCTION
    #[view]
    public fun get_lend_rate<X>(): u64 acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, type_info::type_name<X>());
        return rate.lend_rate
    }

    #[view]
    public fun get_borrow_rate<X>(): u64 acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, type_info::type_name<X>());
        return rate.borrow_rate
    }


    #[view]
    public fun simulate_rewards<T:store, X:store>(address: address): (u64, u64) acquires UserVault, GlobalVault, RateList {
        let user_vault = borrow_global_mut<UserVault>(address);
        let deposited = find_user_deposited(user_vault, type_info::type_name<T>(), type_info::type_name<X>());

        let current_timestamp = timestamp::now_seconds();
        let time_diff = current_timestamp - deposited.last_update;

        // borrow immutably for APY / interest calculations
        let apy = get_apy<T, X>(borrow_global<GlobalVault<T>>(ADMIN));
        let interest_rate = get_interest<T, X>(borrow_global<GlobalVault<T>>(ADMIN));

        let reward = (deposited.deposited * apy * time_diff) / (SECONDS_IN_YEAR * 10000);
        let interest = (deposited.borrowed * interest_rate * time_diff) / (SECONDS_IN_YEAR * 10000);

        (deposited.interest + interest, deposited.rewards + reward)
    }


    fun accrue<T, X: store>(user_vault: &mut Deposited) acquires GlobalVault, RateList{
        let current_timestamp = timestamp::now_seconds();
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let time_diff = current_timestamp - user_vault.last_update;
        if (time_diff == 0) return;

        let reward = (user_vault.deposited * get_apy<T, X>(vault) * time_diff)/ (SECONDS_IN_YEAR * 10000);
        user_vault.rewards = user_vault.rewards + reward;

        let interest = (user_vault.borrowed * get_interest<T, X>(vault) * time_diff)/ (SECONDS_IN_YEAR * 10000);
        user_vault.interest = user_vault.interest + interest;

        user_vault.last_update = current_timestamp;
    }

    fun find_user_deposited(list: &mut UserVault,coin: String,aggr: String): &mut Deposited {
        if (!table::contains(&list.deposited, coin)) {
            table::add(&mut list.deposited, coin, vector::empty<Deposited>());
        };

        let deposits = table::borrow_mut(&mut list.deposited, coin);
        let len = vector::length(deposits);
        let i = 0;

        while (i < len) {
            let deposit = vector::borrow_mut(deposits, i);
            if (deposit.resource == aggr) {
                return deposit;
            };
            i = i + 1;
        };

        // if not found, insert new default Deposited
        let new_dep = Deposited {
            resource: aggr,
            deposited: 0,
            borrowed: 0,
            rewards: 0,
            interest: 0,
            last_update: 0,
            penalty: 0,
        };
        vector::push_back(deposits, new_dep);
        let idx = vector::length(deposits) - 1;
        vector::borrow_mut(deposits, idx)
    }

    fun insert_vault_registry(res: String, vault: String) acquires UserVaultRegistry {
        let user_vault_registry = borrow_global_mut<UserVaultRegistry>(@dev);
        if (!vector::contains(&user_vault_registry.coins, &res)) {
            vector::push_back(&mut user_vault_registry.coins, res);
        };
    }

    fun find_pending_deposit(pending_deposits: &mut vector<PendingDeposit>, res: String): &mut PendingDeposit  {
        let len = vector::length(pending_deposits);
        while(len>0){
            let pending_deposit = vector::borrow_mut(pending_deposits, len-1);
            if(pending_deposit.resource == res){
                return pending_deposit
            };
            len=len-1;            
        };
        abort ERROR_NO_PENDING_DEPOSITS_FOR_THIS_VAULT_PROVIDER
    }

    fun pow10_u256(n: u8): u256 {
        let i = 0u8;
        let p = 1u256;
        while (i < n) {
            p = p * 10;
            i = i + 1;
        };
        p
    }
}
