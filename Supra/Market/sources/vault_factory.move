module dev::AexisVaultFactoryV12{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::option::{Self as option, Option};
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::coin;
    use supra_framework::supra_coin::{Self, SupraCoin};

    const ADMIN: address = @dev;


    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST: u64 = 2;
    const ERROR_TIER_ALREADY_EXISTS: u64 = 3;

    struct Tiers has key {
        table: table::Table<u8, Tier>,
    }

    struct Tier has store, key, drop {
        apr_increase: u16,
        lend_ratio: u16,
        minimal_w_fee: u16,
        deposit_limit: u128,
        borrow_limit: u128
    }

    struct CoinData has store, key, drop {
        resource: String,
        name: String,
        symbol: String,
        decimals: u8,
        supply: Option<u128>, 
    }


    struct VaultList has key, store, copy{
        list: vector<Metadata>,
    }

    struct Metadata has key, store, copy,drop{
        tier: u8,
        resource: String,
        oracleID: u32,
        decimals: u8,
        chain: String
    }

    struct Access has store, key, drop {}


    /// ========== ADMIN CHECK ==========
    fun assert_admin(addr: address) {
        if (addr != ADMIN) {
            abort ERROR_NOT_ADMIN;
        }
    }

    /// ========== INIT ==========
    fun init_module(admin: &signer) acquires Tiers{
        let deploy_addr = signer::address_of(admin);

        if (!exists<Tiers>(deploy_addr)) {
            move_to(admin, Tiers { table: table::new<u8, Tier>() });
        };

        if (!exists<VaultList>(deploy_addr)) {
            move_to(admin, VaultList { list: vector::empty<Metadata>() });
        };

        add_tier(admin, 0, 100, 95, 1, 100_000_000, 75_000_000);
        add_tier(admin, 1, 200, 85, 10, 50_000_000, 20_000_000);
        add_tier(admin, 2, 375, 75, 20, 10_000_000, 7_000_000);
        add_tier(admin, 3, 500, 60, 40, 1_000_000, 500_000);
        add_tier(admin, 4, 750, 50, 80, 600_000, 250_000);
        add_tier(admin, 5, 1000, 30, 125, 250_000, 100_000);
    }


/// ========== ALLOW NEW COIN SOURCE ==========
    public entry fun allow_coin<T>(admin: &signer, tier_id: u8, oracleID: u32, chain: String) acquires VaultList{
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);

        let vault_list = borrow_global_mut<VaultList>(ADMIN);
        let type = type_info::type_name<T>();
            
        vector::push_back(&mut vault_list.list, Metadata { tier: tier_id, resource: type, oracleID: oracleID, decimals: get_coin_decimals<T>(), chain: chain });
    }

    public entry fun change_coin_oracle<T>(admin: &signer, oracleID: u32) acquires VaultList {
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);

        let vault_list = borrow_global_mut<VaultList>(ADMIN);
        let type = type_info::type_name<T>();
            
        let len = vector::length(&vault_list.list);
        while (len > 0) {
            let coin = vector::borrow_mut(&mut vault_list.list, len-1);
            if (coin.resource == type) {
                coin.oracleID = oracleID;
                return
            };
            len = len - 1;
        };
        abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
    }


    public entry fun change_coin_tier<T>(admin: &signer, tier: u8) acquires VaultList{
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);

        let vault_list = borrow_global_mut<VaultList>(ADMIN);
        let type = type_info::type_name<T>();
            
        let len = vector::length(&vault_list.list);
        while(len>0){
            let coin = vector::borrow_mut(&mut vault_list.list, len-1);
            if(coin.resource == type){
                coin.tier = tier;
            };
            len=len-1;
        };
        abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
    }

/// ========== ADD NEW TIER ==========
    public entry fun add_tier(admin: &signer, tier_id: u8, apr_increase: u16, lend_ratio: u16, minimal_w_fee: u16, deposit_limit: u128, borrow_limit: u128) acquires Tiers{
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);

        let tiers = borrow_global_mut<Tiers>(admin_addr);

        if (table::contains(&tiers.table, tier_id)) {
            abort ERROR_TIER_ALREADY_EXISTS; // Tier already exists
        };

        let tier = Tier { apr_increase, lend_ratio, minimal_w_fee, deposit_limit, borrow_limit };
        table::add(&mut tiers.table, tier_id, tier);
    }

/// ========== UPDATE EXISTING TIER ==========
    public entry fun update_tier(admin: &signer, tier_id: u8, apr_increase: u16, lend_ratio: u16, minimal_w_fee: u16, deposit_limit: u128, borrow_limit: u128) acquires Tiers {
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);

        let tiers = borrow_global_mut<Tiers>(admin_addr);

        if (!table::contains(&tiers.table, tier_id)) {
            abort 11; // Tier does not exist
        };

        let tier_ref = table::borrow_mut(&mut tiers.table, tier_id);
        tier_ref.apr_increase = apr_increase;
        tier_ref.lend_ratio = lend_ratio;
        tier_ref.minimal_w_fee = minimal_w_fee;
        tier_ref.deposit_limit = deposit_limit;
        tier_ref.borrow_limit = borrow_limit;
    }

/// ========== GET TIER ==========
    #[view]
    public fun get_tier(tier_id: u8): Tier acquires Tiers {
        let tiers = borrow_global<Tiers>(ADMIN);
        let tier = table::borrow(&tiers.table, tier_id);
        Tier { apr_increase: tier.apr_increase, lend_ratio: tier.lend_ratio, minimal_w_fee: tier.minimal_w_fee, deposit_limit: tier.deposit_limit, borrow_limit: tier.borrow_limit }
    }

    public fun apr_increase(tier_id: u8): u16 acquires Tiers{
        let tier = get_tier(tier_id);
        tier.apr_increase
    }

    public fun lend_ratio(tier_id: u8): u16 acquires Tiers{
        let tier = get_tier(tier_id);
        tier.lend_ratio
    }

    public fun minimal_w_fee(tier_id: u8): u16 acquires Tiers{
        let tier = get_tier(tier_id);
        tier.minimal_w_fee
    }

    public fun deposit_limit(tier_id: u8): u128 acquires Tiers{
        let tier = get_tier(tier_id);
        tier.deposit_limit
    }

    public fun borrow_limit(tier_id: u8): u128 acquires Tiers{
        let tier = get_tier(tier_id);
        tier.borrow_limit
    }


/// ========== GET COIN DATA ==========
    #[view]
    public fun get_coin_data<T>(): CoinData {
        let type = type_info::type_name<T>();
        CoinData { resource: type, name: coin::name<T>(), symbol: coin::symbol<T>(), decimals: coin::decimals<T>(), supply: coin::supply<T>() }
    }

    public fun get_coin_type<T>(): String {
        let coin_data = get_coin_data<T>();
        coin_data.resource
    }

    public fun get_coin_name<T>(): String {
        let coin_data = get_coin_data<T>();
        coin_data.name
    }

    public fun get_coin_symbol<T>(): String {
        let coin_data = get_coin_data<T>();
        coin_data.symbol
    }

    public fun get_coin_decimals<T>(): u8 {
        let coin_data = get_coin_data<T>();
        coin_data.decimals
    }

    public fun get_coin_supply<T>(): Option<u128> {
        let coin_data = get_coin_data<T>();
        coin_data.supply
    }

    public fun get_coin_chain<T>(): Option<u128> {
        let coin_data = get_coin_data<T>();
        coin_data.supply
    }




/// ========== GET COIN METADATA ==========

    #[view]
    public fun get_registered_vaults(): vector<Metadata> acquires VaultList {
        let vault_list = borrow_global<VaultList>(ADMIN);
        vault_list.list
    }

    #[view]
    public fun get_coin_metadata<T>(): Metadata acquires VaultList {
        let vault_list = borrow_global<VaultList>(ADMIN);
        let len = vector::length(&vault_list.list);
        let type = type_info::type_name<T>();
        while(len>0){
            let metadat = vector::borrow(&vault_list.list, len-1);
            if(metadat.resource == type){
                return *metadat
            };
            len=len-1;
        };
    abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
    }

    public fun get_coin_metadata_tier(metadata: &Metadata): u8 {
        metadata.tier
    }

    public fun get_coin_metadata_resource(metadata: &Metadata): String {
        metadata.resource
    }

    public fun get_coin_metadata_oracle(metadata: &Metadata): u32 {
        metadata.oracleID
    }

    public fun get_coin_metadata_decimals(metadata: &Metadata): u8 {
        metadata.decimals
    }

    public fun get_coin_metadata_by_res(res: &String): Metadata acquires VaultList {
        let list = borrow_global<VaultList>(ADMIN);
        let n = vector::length(&list.list);
        let i = 0;
        while (i < n) {
            let m_ref = vector::borrow(&list.list, i);
            if (String::bytes(&m_ref.resource) == String::bytes(res)) {
                return *m_ref; // return by value (copy)
            };
            i = i + 1;
        };
        abort ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST
    }


}
