module dev::aexisVaultAllowedCoinsV5 {
    use std::signer;
    use std::string::{String, utf8};
    use std::timestamp;
    use std::option::{Option};
    use std::vector;
    use std::type_info;
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

    const ADMIN: address = @dev;

    const SECONDS_IN_YEAR: u64 = 31_536_000; // 365 days
    const DEFAULT_SUPPLY_APY_BPS: u64 = 5000000; // 50000% APY
    const DEFAULT_BORROW_APY_BPS: u64 = 10000000; // 100000% APY
    const BASE_APY_BPS: u64 = 200;    // 2%
    const BONUS_SCALE_BPS: u64 = 3000; // k = 0.3

    const MAX_COLLATERAL_RATIO: u64 = 80; // Safe borrowing limit (%)
    const LIQUIDATION_THRESHOLD: u64 = 85; // Liquidation trigger (%)
    const LIQUIDATION_BONUS_BPS: u64 = 500; // 5% bonus to liquidator


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

    struct VaultList has key, store{
        list: vector<Metadata>
    }


    struct Metadata has key, store{
        resource: vector<String>,
        oracleID: u32,
        lend_rate: u16,
    }


    struct CoinData has store, key{
        resource: String,
        name: String,
        symbol: String,
        decimals: u8,
        supply: Option<u128>,
    }

    struct CompleteVault has key{
        vault: Vault,
        coin: CoinData
    }

    struct Access has store, key, drop {}

    fun get_admin(): address {
        ADMIN
    }

    fun init_module(address: &signer){
        let deploy_addr = signer::address_of(address);

        if (!exists<VaultList>(deploy_addr)) {
            move_to(address, VaultList { list: vector::empty<String>()});
        };
    }


    public entry fun init_vault<T>(admin: &signer, oracleID: u32, lend_rate: u16) acquires VaultList{
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault<T>>(ADMIN)) {

            let vault_list = borrow_global_mut<VaultList>(ADMIN);
            let type = type_info::type_name<T>();

            move_to(admin, GlobalVault {
                total_deposited: 0,
                balance: coin::zero<T>(),
            });
            
            vector::push_back(&mut vault_list.list, Metadata { resource: type, oracleID: oracleID, lend_rate: lend_rate  });
        }
    }


    public entry fun init_user_vault(user: &signer) {
        let addr = signer::address_of(user);
        if (!exists<UserVaultList>(addr)) {
            move_to(user, UserVaultList { list: vector::empty<UserVault>() });
        };
    }


    #[view]
    public fun get_registered_vaults(): vector<Metadata> acquires VaultList {
        let vault_list = borrow_global<VaultList>(ADMIN);
        vault_list.list
    }

    #[view]
    public fun get_complete_vault<T>(): CompleteVault acquires GlobalVault {
        let type = type_info::type_name<T>();
        CompleteVault { vault: get_vault<T>(), coin: get_coin_data<T>() }
    }

    #[view]
    public fun get_coin_data<T>(): CoinData {
        let type = type_info::type_name<T>();
        CoinData { resource: type, name: coin::name<T>(), symbol: coin::symbol<T>(), decimals: coin::decimals<T>(), supply: coin::supply<T>() }
    }

    #[view]
    public fun get_vault<T>(): Vault acquires GlobalVault {
        assert!(exists<GlobalVault<T>>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(ADMIN);
        let balance = coin::value(&vault.balance);
        Vault {total_deposited: vault.total_deposited,balance,borrowed: vault.total_deposited - balance, utilization: get_utilization_ratio<T>(), rewards: get_apy<T>(), interest: get_interest<T>()}
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


    public fun get_oracle_id(list: &vector<Metadata>, res: &String): (u32) {
        let n = vector::length(list);
        let i = 0;
        while (i < n) {
            let m = vector::borrow(list, i);
            if (String::bytes(m.resource) == String::bytes(*res)) {
                return (m.oracle_id);
            };
            i = i + 1;
        };
        (0)
    }


    public fun find_or_insert(list: &mut vector<UserVault>, res: String): &mut UserVault {
        let n = vector::length(list);
        let i = 0;
        while (i < n) {
            let v = vector::borrow_mut(list, i);
            if (std::string::bytes(v.resource) == std::string::bytes(res)) {
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
            }
        );
        vector::borrow_mut(list, idx)
    }


}
