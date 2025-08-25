module dev::AexisVaultsV3 {
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
    use dev::AexisVaultFactoryV3::{Self as Factory, Tier, CoinData};

    use dev::AexisCoinTypes::{Self as coins, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC };

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
    }

    struct Access has store, key, drop {}

    struct UserCap has store, key, drop {}

    public fun give_access(s: &signer): Access {
        Access {}
    }

    public fun give_usercap(s: &signer, access: Access): UserCap {
        // access is consumed automatically
        UserCap {}
    }


    #[event]
    struct DepositEvent has copy, drop, store {
        amount: u64,
        from: address,
        token: String,
    }



    #[event]
    struct BridgedDepositEvent has copy, drop, store {
        validator: address,
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

    public entry fun init_all_vaults(address: &signer){
        init_vault<coins::BaseEthereum>(address, 1, 1);
        init_vault<BaseUSDC>(address, 0, 47);

        init_vault<SuiEthereum>(address, 1, 1);
        init_vault<SuiUSDC>(address, 0, 47);
        init_vault<SuiUSDT>(address, 0, 47);
        init_vault<SuiSui>(address, 2, 90);
        init_vault<SuiBitcoin>(address, 1, 0);

        init_vault<SupraCoin>(address, 3, 500);
    }

    fun init_module(address: &signer){
     //   init_vault<coins::BaseEthereum>(address, 1, 1);
     //   init_vault<BaseUSDC>(address, 0, 47);

     //   init_vault<SuiEthereum>(address, 1, 1);
     //   init_vault<SuiUSDC>(address, 0, 47);
     ///   init_vault<SuiUSDT>(address, 0, 47);
      //  init_vault<SuiSui>(address, 2, 90);
      //  init_vault<SuiBitcoin>(address, 1, 0);

      //  init_vault<SupraCoin>(address, 3, 500);
    }

    public entry fun init_vault<T>(admin: &signer, tier: u8, oracleID: u32){
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(ADMIN)) {

            let type = type_info::type_name<T>();
            move_to(admin, GlobalVault {
                tier: tier,
                total_deposited: 0,
                balance: coin::zero<T>(),
                external_rewards: 0,
                external_interest: 0,
            });
            Factory::allow_coin<T>(admin, tier, oracleID);
        }
    }


    public entry fun init_user_vault(user: &signer) {
        let addr = signer::address_of(user);
        if (!exists<UserVaultList>(addr)) {
            move_to(user, UserVaultList { list: vector::empty<UserVault>() });
        };
    }


    public fun bridge_deposit<T>(user: &signer, access: Access, user_cap: UserCap, recipient: address, amount: u64, coins: Coin<T>) acquires GlobalVault, UserVaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        assert!(exists<UserVaultList>(recipient), ERROR_USER_VAULT_NOT_INITIALIZED);
        //assert!(exists<UserCap>(signer::address_of(user)), 1);
        let vault = borrow_global_mut<GlobalVault<T>>(ADMIN);

        let user_vault_list = borrow_global_mut<UserVaultList>(recipient);

        let type_str = type_info::type_name<T>();
        let user_vault = find_or_insert(&mut user_vault_list.list, type_str);

        //let coins = BridgedCoins::extract_to<T>(user, recipient, amount);
        coin::merge(&mut vault.balance, coins);

        vault.total_deposited = vault.total_deposited + amount;
        user_vault.deposited = user_vault.deposited + amount;

        accrue<T>(user_vault);

        event::emit(BridgedDepositEvent {
            validator:  signer::address_of(user), 
            amount, 
            from: recipient,
            token: type_info::type_name<T>() 
        });
    }

    public entry fun deposit<T>(user: &signer, amount: u64) acquires GlobalVault, UserVaultList {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        assert!(exists<UserVaultList>(signer::address_of(user)), ERROR_USER_VAULT_NOT_INITIALIZED);
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

    public entry fun borrow<T>(user: &signer, amount: u64) acquires GlobalVault, UserVaultList {
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

    public entry fun liquidate<T>(liquidator: &signer,  borrower_addr: address) acquires GlobalVault, UserVaultList {

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
    public fun get_complete_vault<T>(): CompleteVault acquires GlobalVault {
        let vault = get_vault<T>();
        CompleteVault { vault: vault, coin: Factory::get_coin_data<T>(), tier: Factory::get_tier(vault.tier)  }
    }

    #[view]
    public fun get_vault<T>(): VaultUSD acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let balance = coin::value(&vault.balance);
        let metadata = Factory::get_coin_metadata_by_res(&type_info::type_name<T>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        let denom = pow10_u256((price_decimals as u8));
        VaultUSD {tier: vault.tier, oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: vault.total_deposited,balance,borrowed: vault.total_deposited - balance, utilization:  get_utilization_ratio<T>(vault), rewards: get_apy<T>(vault), interest: get_interest<T>(vault), external_interest: vault.external_interest,  external_rewards: vault.external_rewards, fee: get_withdraw_fee(get_utilization_ratio<T>(vault))}
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
    public fun get_user_collatelar_ratio<T>(address: address): u64 acquires UserVaultList {
        let vault = get_user_vault<T>(address);
        (vault.borrowed * 100) / vault.deposited
    }

    fun get_apy<T>(vault: &GlobalVault<T>): u64{
        let utilization = get_utilization_ratio<T>(vault); // in %
        let tier = Factory::get_tier(vault.tier);
        let minimum_apr = Factory::apr_increase(vault.tier);
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(utilization > 110){
            u_bps2 = 10_999;
        };
        return (((u_bps) * 2_000) / (11_000 - u_bps2) + (minimum_apr as u64))
    }

    fun get_interest<T>(vault: &GlobalVault<T>): u64{
        let utilization = get_utilization_ratio<T>(vault); // in %
        let tier = Factory::get_tier(vault.tier);
        let minimum_apr = Factory::apr_increase(vault.tier);
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(utilization > 110){
            u_bps2 = 7499;
        };
        return (((u_bps) * 3_000) / (7500 - u_bps2) + (minimum_apr as u64)*2)
    }


    #[view]
    public fun get_user_position_usd<T>(addr: address): (u256, u256, u256, u256) acquires UserVaultList {
        let uv = get_user_vault<T>(addr);

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
    public fun get_user_total_usd(addr: address): (u256, u256, u256, u256) acquires UserVaultList, {
        assert!(exists<UserVaultList>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        let user_vault_list = borrow_global<UserVaultList>(addr);

        let total_dep = 0u256;
        let total_bor = 0u256;
        let total_rew = 0u256;
        let total_int = 0u256;

        let n = vector::length(&user_vault_list.list);
        let i = 0;
        while (i < n) {
            let uv = vector::borrow(&user_vault_list.list, i);

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


            i = i + 1;
        };
        (total_dep, total_bor, total_rew, total_int)
    }

  /*  #[view]
    public fun get_total_vault(addr: address): (u256, u256, u16, u32)  {
        let list = Factory::get_registered_vaults();

        let total_dep = 0u256;
        let total_bor = 0u256;
        let utilization = 0u16;
        let withdraw_fee = 0u32;

        let n = vector::length(&list);
        let i = 0;
        while (i < n) {
            let v = vector::borrow(&list, i);

            // metadata for resource (contains oracleID, lend_rate, coin_decimals, etc.)
            let metadata = Factory::get_coin_metadata_by_res(&v.resource);

            // fetch oracle price
            let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
            let x = get_vault<a>();

            // denominator = 10^(coin_decimals + price_decimals)
            let denom = pow10_u256((price_decimals as u8));
            
            // deposited/borrowed value in USD
            let dep_usd = ((x.deposited as u256) * (price as u256)) / denom;
            let bor_usd = ((x.borrowed  as u256) * (price as u256)) / denom;

            // apply lend rate (assumed %)
            total_dep = total_dep + (dep_usd * (Factory::lend_rate(Factory::get_coin_metadata_tier(&metadata)) as u256)) / 100;
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
    public fun simulate_rewards<T>(address: address): (u64, u64) acquires GlobalVault, UserVaultList {
        let user_vault_list = borrow_global_mut<UserVaultList>(address);
        let user_vault = find_or_insert(&mut user_vault_list.list, type_info::type_name<T>());

        let current_timestamp = timestamp::now_seconds();
        let time_diff = current_timestamp - user_vault.last_update;

        // borrow immutably for APY / interest calculations
        let apy = get_apy<T>(borrow_global<GlobalVault<T>>(ADMIN));
        let interest_rate = get_interest<T>(borrow_global<GlobalVault<T>>(ADMIN));

        let reward = (user_vault.deposited * apy * time_diff) / (SECONDS_IN_YEAR * 10000);
        let interest = (user_vault.borrowed * interest_rate * time_diff) / (SECONDS_IN_YEAR * 10000);

        (user_vault.interest + interest, user_vault.rewards + reward)
    }


    fun accrue<T>(user_vault: &mut UserVault) acquires GlobalVault{
        let current_timestamp = timestamp::now_seconds();
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let time_diff = current_timestamp - user_vault.last_update;
        if (time_diff == 0) return;

        let reward = (user_vault.deposited * get_apy<T>(vault) * time_diff)
            / (SECONDS_IN_YEAR * 10000);
        user_vault.rewards = user_vault.rewards + reward;

        let interest = (user_vault.borrowed * get_interest<T>(vault) * time_diff)
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
