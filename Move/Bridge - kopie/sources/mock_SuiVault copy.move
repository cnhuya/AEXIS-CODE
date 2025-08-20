module dev::aexisVaultV14 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::option::{Option};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::coin;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use supra_framework::event;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 2;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 3;
    const ERROR_USER_VAULT_NOT_INITIALIZED: u64 = 4;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 5;
    const ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION: u64 = 6;
    const ERROR_INVALID_COIN_TYPE: u64 = 6;
    const ERROR_BORROW_COLLATERAL_OVERFLOW: u64 = 7;
    const ERROR_INSUFFICIENT_COLLATERAL: u64 = 8;

    const ADMIN: address = @dev;

    const SECONDS_IN_YEAR: u64 = 31_536_000; // 365 days
    const DEFAULT_SUPPLY_APY_BPS: u64 = 5000000; // 50000% APY
    const DEFAULT_BORROW_APY_BPS: u64 = 10000000; // 100000% APY
    const BASE_APY_BPS: u64 = 200;    // 2%
    const BONUS_SCALE_BPS: u64 = 3000; // k = 0.3

    const MAX_COLLATERAL_RATIO: u64 = 80; // Safe borrowing limit (%)
    const LIQUIDATION_THRESHOLD: u64 = 85; // Liquidation trigger (%)
    const LIQUIDATION_BONUS_BPS: u64 = 500; // 5% bonus to liquidator

    struct UserVaultList has key, store, copy {
        list: vector<UserVault>
    }

    struct UserVault has store, key, copy, drop {
        resource: String,
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
        last_update: u64,
        penalty: u64,
    }

    struct GlobalVault<phantom T> has key {
        total_deposited: u64,
        balance: coin::Coin<T>,
    }

    struct Vault has store, copy, drop {
        total_deposited: u64,
        balance: u64,
        borrowed: u64,
        utilization: u64,
        rewards: u64,
        interest: u64,
    }

    struct VaultUSD has store, copy, drop {
        oracle_price: u128,
        oracle_decimals: u8,
        total_deposited: u64,
        balance: u64,
        borrowed: u64,
        utilization: u64,
        rewards: u64,
        interest: u64,
        fee: u64,
    }



    struct VaultList has key, store, copy{
        list: vector<Metadata>
    }


    struct Metadata has key, store, copy, drop{
        resource: String,
        decimals: u8,
        oracleID: u32,
        lend_rate: u16,
    }


    struct CoinData has store, key, drop{
        resource: String,
        name: String,
        symbol: String,
        decimals: u8,
        supply: Option<u128>, // match coin::supply<T>()
    }

    struct CompleteVault has key{
        vault: VaultUSD,
        coin: CoinData
    }

    struct Access has store, key, drop {}

    #[event]
    struct DepositEvent has copy, drop, store {
        amount: u64,
        from: address,
        token: String,
    }

    #[event]
    struct WithdrawEvent has copy, drop, store {
        amount: u64,
        to: address,
    }

    #[event]
    struct BorrowEvent has copy, drop, store {
        amount: u64,
        to: address,
    }

    

    #[event]
    struct ClaimRewardsEvent has copy, drop, store {
        amount: u64,
        to: address,
    }

    #[event]
    struct PayInterestEvent has copy, drop, store {
        amount: u64,
        from: address,
    }


    #[event]
    struct LiquidationEvent has copy, drop, store {
        borrower: address,
        liquidator: address,
        repaid: u64,
        collateral_seized: u64,
    }

    fun get_admin(): address {
        ADMIN
    }

    fun init_module(address: &signer){
        let deploy_addr = signer::address_of(address);

        if (!exists<VaultList>(deploy_addr)) {
            move_to(address, VaultList { list: vector::empty<Metadata>()});
        };
    }



    public entry fun init_vault<T>(admin: &signer, oracleID: u32, lend_rate: u16) acquires VaultList{
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(ADMIN)) {

            let vault_list = borrow_global_mut<VaultList>(ADMIN);
            let type = type_info::type_name<T>();
            let typeinfo = type_info::type_of<T>();

            let coindata = get_coin_data<T>();
            move_to(admin, GlobalVault {
                total_deposited: 0,
                balance: coin::zero<T>(),
            });
            
            vector::push_back(&mut vault_list.list, Metadata { resource: type, decimals: coindata.decimals, oracleID: oracleID, lend_rate: lend_rate  });
        }
    }


    public entry fun init_user_vault(user: &signer) {
        let addr = signer::address_of(user);
        if (!exists<UserVaultList>(addr)) {
            move_to(user, UserVaultList { list: vector::empty<UserVault>() });
        };
    }


    public entry fun deposit<T>(user: &signer, amount: u64) acquires GlobalVault, UserVaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        assert!(exists<UserVaultList>(ADMIN), ERROR_USER_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let user_vault_list = borrow_global_mut<UserVaultList>(signer::address_of(user));

        let type_str = type_info::type_name<T>();
        let user_vault = find_or_insert(&mut user_vault_list.list, type_str);

        let coins = coin::withdraw<T>(user, amount);
        coin::merge(&mut vault.balance, coins);

        vault.total_deposited = vault.total_deposited + amount;
        user_vault.deposited = user_vault.deposited + amount;

        accrue<T>(user_vault);

        event::emit(DepositEvent { 
            amount, 
            from: signer::address_of(user), 
            token: type_info::type_name<T>() 
        });
    }


    public entry fun withdraw<T>(user: &signer, amount: u64) acquires GlobalVault, UserVaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let user_vault_list = borrow_global_mut<UserVaultList>(signer::address_of(user));

        let type_str = type_info::type_name<T>();
        let user_vault = find_or_insert(&mut user_vault_list.list, type_str);

        assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        vault.total_deposited = vault.total_deposited - amount;
        user_vault.deposited = user_vault.deposited - amount;

        accrue<T>(user_vault);
        event::emit(WithdrawEvent { amount, to: signer::address_of(user) });
    }

    public entry fun borrow<T>(user: &signer, amount: u64) acquires GlobalVault, UserVaultList, VaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let type_str = type_info::type_name<T>();

        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let valueUSD = getValue(type_str, (amount as u256));
        let (depoUSD, borrowUSD, _, _) = get_user_total_usd(signer::address_of(user));

        let user_vault_list = borrow_global_mut<UserVaultList>(signer::address_of(user));

        let user_vault = find_or_insert(&mut user_vault_list.list, type_str);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        user_vault.borrowed = user_vault.borrowed + amount;
        accrue<T>(user_vault);
        event::emit(BorrowEvent { amount, to: signer::address_of(user) });
    }

    public entry fun claim_rewards<T>(user: &signer,) acquires GlobalVault, UserVaultList {
        let addr = signer::address_of(user);
        let user_vault_list = borrow_global_mut<UserVaultList>(signer::address_of(user));

        let type_str = type_info::type_name<T>();
        let user_vault = find_or_insert(&mut user_vault_list.list, type_str);

        accrue<T>(user_vault);

        let reward_amount = user_vault.rewards;
        let interest_amount = user_vault.interest;
        user_vault.interest = 0;
        user_vault.rewards = 0;
        let global_vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        
        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(coin::value(&global_vault.balance) >= reward, ERROR_NOT_ENOUGH_LIQUIDITY);
            let coins = coin::extract(&mut global_vault.balance, reward);
            coin::deposit(addr, coins);

            event::emit(ClaimRewardsEvent { amount: reward, to: signer::address_of(user) });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            user_vault.deposited = user_vault.deposited - interest;

            event::emit(PayInterestEvent { amount: interest, from: signer::address_of(user) }); 
        }

    }

    public entry fun liquidate<T>(liquidator: &signer,  borrower_addr: address) acquires GlobalVault, UserVaultList, VaultList {

        let type_str = type_info::type_name<T>();

        let (depoUSD, borrowUSD, _, _) = get_user_total_usd(signer::address_of(liquidator));

        assert!(depoUSD < borrowUSD, ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION);

        let repayUSD = borrowUSD - depoUSD;
        let repayCoin = getValueByCoin(type_str, repayUSD);
        let user_vault_list = borrow_global_mut<UserVaultList>(signer::address_of(liquidator));
        let user_vault = find_or_insert(&mut user_vault_list.list, type_str);

        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);

        accrue<T>(user_vault);
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
        user_vault.penalty = user_vault.penalty + (total_deduction as u64);

        event::emit(LiquidationEvent {
            borrower: borrower_addr,
            liquidator: signer::address_of(liquidator),
            repaid: (repayCoin as u64),
            collateral_seized: (bonus as u64),
        });
    }

    #[view]
    public fun get_registered_vaults(): vector<Metadata> acquires VaultList {
        let vault_list = borrow_global<VaultList>(ADMIN);
        vault_list.list
    }

    #[view]
    public fun get_complete_vault<T>(): CompleteVault acquires GlobalVault, VaultList {
        let type = type_info::type_name<T>();
        CompleteVault { vault: get_vault<T>(), coin: get_coin_data<T>() }
    }

    #[view]
    public fun get_coin_data<T>(): CoinData {
        let type = type_info::type_name<T>();
        CoinData { resource: type, name: coin::name<T>(), symbol: coin::symbol<T>(), decimals: coin::decimals<T>(), supply: coin::supply<T>() }
    }

    #[view]
    public fun get_vault<T>(): VaultUSD acquires GlobalVault, VaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let balance = coin::value(&vault.balance);

        let vault_list = borrow_global<VaultList>(ADMIN);
        let metadata = lookup_metadata(&vault_list.list, &type_info::type_name<T>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadata.oracleID);
        let denom = pow10_u256((price_decimals as u8));
        VaultUSD {oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: vault.total_deposited,balance,borrowed: vault.total_deposited - balance, utilization:  get_utilization_ratio<T>(), rewards: get_apy<T>(), interest: get_interest<T>(), fee: get_withdraw_fee( get_utilization_ratio<T>())}
    }

    #[view]
    public fun get_vault_balance<T>(): u64 acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        coin::value(&vault.balance)
    }

    #[view]
    public fun get_user_vault<T>(addr: address): UserVault acquires UserVaultList {
        assert!(exists<UserVaultList>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        let v = borrow_global<UserVaultList>(addr);
        let len = vector::length(&v.list);
        let type = type_info::type_name<T>();
        while(len>0){
            let vault = vector::borrow(&v.list, len-1);
            if(vault.resource == type){
                return *vault
            };
            len=len-1;
        };
        abort(0)
    }


    #[view]
    public fun get_user_vaults(addr: address): vector<UserVault> acquires UserVaultList {
        assert!(exists<UserVaultList>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        let v = borrow_global<UserVaultList>(addr);
        v.list
    }

    #[view]
    public fun get_utilization_ratio<T>(): u64 acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let borrowed = vault.total_deposited - coin::value(&vault.balance);
        if (vault.total_deposited == 0) {
            0
        } else {
            (borrowed * 100) / vault.total_deposited
        }
    }

    #[view]
    public fun get_user_collatelar_ratio<T>(address: address): u64 acquires UserVaultList {
        let vault = get_user_vault<T>(address);
        (vault.borrowed * 100) / vault.deposited
    }

    #[view]
    public fun get_apy<T>(): u64 acquires GlobalVault {
        let utilization = get_utilization_ratio<T>(); // in %
        let base = BASE_APY_BPS*5; // e.g., 200 = 2%
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(utilization > 110){
            u_bps2 = 10_999;
        };
        let bonus = ((u_bps) * 2_000) / (11_000 - u_bps2);
        return (base + bonus)
    }

    #[view]
    public fun get_interest<T>(): u64 acquires GlobalVault {
        let utilization = get_utilization_ratio<T>(); // in %
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(utilization > 110){
            u_bps2 = 7499;
        };
        let bonus = ((u_bps) * 3_000) / (7500 - u_bps2);
        return (bonus)
    }


    #[view]
    public fun get_user_position_usd<T>(addr: address): (u256, u256, u256, u256) acquires UserVaultList, VaultList {
        let uv = get_user_vault<T>(addr);

        // get coin decimals
        let coin_decimals = coin::decimals<T>();

        // lookup oracle metadata
        let vault_list = borrow_global<VaultList>(ADMIN);
        let metadata = lookup_metadata(&vault_list.list, &uv.resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadata.oracleID);

        

        // normalize amount * price / 10^coin_decimals
        let denom = pow10_u256(metadata.decimals + (price_decimals as u8));

        let dep_usd = ((((uv.deposited as u256) * (price as u256)) / denom)*(metadata.lend_rate as u256))/100;
        let bor_usd = ((uv.borrowed as u256)  * (price as u256)) / denom;
        let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
        let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

        (dep_usd, bor_usd, reward_usd ,interest_usd)
    }


    #[view]
    public fun get_user_total_usd(addr: address): (u256, u256, u256, u256) acquires UserVaultList, VaultList {
        assert!(exists<UserVaultList>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        let user_vault_list = borrow_global<UserVaultList>(addr);
        let vault_list = borrow_global<VaultList>(ADMIN);

        let total_dep = 0u256;
        let total_bor = 0u256;
        let total_rew = 0u256;
        let total_int = 0u256;

        let n = vector::length(&user_vault_list.list);
        let i = 0;
        while (i < n) {
            let uv = vector::borrow(&user_vault_list.list, i);

            // metadata for resource (contains oracleID, lend_rate, coin_decimals, etc.)
            let metadata = lookup_metadata(&vault_list.list, &uv.resource);
            // fetch oracle price
            let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadata.oracleID);

            // denominator = 10^(coin_decimals + price_decimals)
            let denom = pow10_u256(metadata.decimals + (price_decimals as u8));

            // deposited/borrowed value in USD
            let dep_usd = ((uv.deposited as u256) * (price as u256)) / denom;
            let bor_usd = ((uv.borrowed  as u256) * (price as u256)) / denom;
            let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
            let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

            // apply lend rate (assumed %)
            total_dep = total_dep + (dep_usd * (metadata.lend_rate as u256)) / 100;
            total_bor = total_bor + bor_usd;
            total_rew = total_rew + reward_usd;
            total_int = total_int + interest_usd;


            i = i + 1;
        };
        (total_dep, total_bor, total_rew, total_int)
    }

  /*  #[view]
    public fun get_total_vault(addr: address): (u256, u256, u16, u32) acquires VaultList {
        let vault_list = borrow_global<VaultList>(ADMIN);

        let total_dep = 0u256;
        let total_bor = 0u256;
        let utilization = 0u16;
        let withdraw_fee = 0u32;

        let n = vector::length(&vault_list.list);
        let i = 0;
        while (i < n) {
            let v = vector::borrow(&vault_list.list, i);

            // metadata for resource (contains oracleID, lend_rate, coin_decimals, etc.)
            let metadata = lookup_metadata(&vault_list.list, &v.resource);

            // fetch oracle price
            let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadata.oracleID);
            let a = metadata.type;
            let x = get_vault<a>();

            // denominator = 10^(coin_decimals + price_decimals)
            let denom = pow10_u256((price_decimals as u8));
            
            // deposited/borrowed value in USD
            let dep_usd = ((x.deposited as u256) * (price as u256)) / denom;
            let bor_usd = ((x.borrowed  as u256) * (price as u256)) / denom;

            // apply lend rate (assumed %)
            total_dep = total_dep + (dep_usd * (metadata.lend_rate as u256)) / 100;
            total_bor = total_bor + bor_usd;

            i = i + 1;
        };
        utilization = (((total_bor*100)/total_dep) as u16);
        (total_dep, total_bor, utilization, get_withdraw_fee(utilization))
    }
*/

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

    fun getValue(resource: String, amount: u256): u256 acquires VaultList{
        assert!(exists<VaultList>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault_list = borrow_global<VaultList>(ADMIN);
        let metadata = lookup_metadata(&vault_list.list, &resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadata.oracleID);
        let denom = pow10_u256(metadata.decimals + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / denom
    }

    fun getValueByCoin(resource: String, amount: u256): u256 acquires VaultList{
        assert!(exists<VaultList>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault_list = borrow_global<VaultList>(ADMIN);
        let metadata = lookup_metadata(&vault_list.list, &resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadata.oracleID);
        let denom = pow10_u256(metadata.decimals + (price_decimals as u8));
        return ((amount as u256) / (price as u256)) / denom
    }

    #[view]
    public fun simulate_rewards<T>(address: address): (u64, u64) acquires GlobalVault, UserVaultList{
        let user_vault_list = borrow_global_mut<UserVaultList>(address);
        let user_vault = find_or_insert(&mut user_vault_list.list, type_info::type_name<T>());
        let current_timestamp = timestamp::now_seconds();
        let time_diff = current_timestamp - user_vault.last_update;

        let reward = (user_vault.deposited * get_apy<T>() * time_diff) / (SECONDS_IN_YEAR * 10000);

        let interest = (user_vault.borrowed * get_interest<T>() * time_diff)/ (SECONDS_IN_YEAR * 10000);

        return ((user_vault.interest + interest),(user_vault.rewards + reward))
    }

    fun accrue<T>(user_vault: &mut UserVault) acquires GlobalVault{
        let current_timestamp = timestamp::now_seconds();
        let time_diff = current_timestamp - user_vault.last_update;
        if (time_diff == 0) return;

        let reward = (user_vault.deposited * get_apy<T>() * time_diff)
            / (SECONDS_IN_YEAR * 10000);
        user_vault.rewards = user_vault.rewards + reward;

        let interest = (user_vault.borrowed * get_interest<T>() * time_diff)
            / (SECONDS_IN_YEAR * 10000);
        user_vault.interest = user_vault.interest + interest;

        user_vault.last_update = current_timestamp;
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


    fun lookup_metadata(list: &vector<Metadata>, res: &String): Metadata {
        let n = vector::length(list);
        let i = 0;
        while (i < n) {
            let m = vector::borrow(list, i);
            if (String::bytes(&m.resource) == String::bytes(res)) {
                return *m
            };
            i = i + 1;
        };
        abort(ERROR_INVALID_COIN_TYPE) // fallback if not found
    }


    fun find_or_insert(list: &mut vector<UserVault>, res: String): &mut UserVault {
        let n = vector::length(list);
        let i = 0;
        while (i < n) {
            let v = vector::borrow_mut(list, i);
            if (String::bytes(&v.resource) == String::bytes(&res)) {
                return v;
            };
            i = i + 1;
        };

        // if not found, append new
        let idx = vector::length(list);
        vector::push_back(
            list,
            UserVault {
                resource: res,
                deposited: 0,
                borrowed: 0,
                rewards: 0,
                interest: 0,
                last_update: timestamp::now_seconds(),
                penalty: 0,
            }
        );
        vector::borrow_mut(list, idx)
    }


}
