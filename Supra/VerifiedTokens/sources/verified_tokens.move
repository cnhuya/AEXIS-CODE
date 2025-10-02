module dev::QiaraVerifiedTokensV6{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use std::option::{Option};
    use supra_oracle::supra_oracle_storage;
    use supra_framework::coin;
    use supra_framework::supra_coin::{Self, SupraCoin};

    use dev::QiaraStorageV22::{Self as storage};
    use dev::QiaraMath::{Self as Math};
    use dev::QiaraCoinTypesV5::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST: u64 = 2;
    const ERROR_TIER_ALREADY_EXISTS: u64 = 3;
    const ERROR_COIN_ALREADY_ALLOWED: u64 = 4;

// === STRUCTS === //
    struct Tiers has key {
        table: table::Table<u8, Tier>,
    }

    struct Tier has store, key, drop {
        apr_increase: u16, // base borrow interest
        lend_ratio: u16,
        minimal_w_fee: u16,
        deposit_limit: u128,
        borrow_limit: u128,
    }

    struct Tokens has key, store, copy{
        list: vector<Metadata>,
    }

    struct Metadata has key, store, copy,drop{
        tier: u8,
        resource: String,
        price: u128,
        denom: u256,
        oracleID: u32,
        decimals: u8,
        chain: String
    }

    // View Struct
    struct CoinData has store, key, drop {
        resource: String,
        name: String,
        symbol: String,
        decimals: u8,
        supply: Option<u128>, 
    }

// === INIT === //
    fun init_module(admin: &signer) acquires Tiers, Tokens{
        let deploy_addr = signer::address_of(admin);

        if (!exists<Tiers>(deploy_addr)) {
            move_to(admin, Tiers { table: table::new<u8, Tier>() });
        };

        if (!exists<Tokens>(deploy_addr)) {
            move_to(admin, Tokens { list: vector::empty<Metadata>() });
        };

        add_tier(admin, 0, 100, 95, 100, 100_000_000, 75_000_000);
        add_tier(admin, 1, 200, 85, 250, 50_000_000, 20_000_000);
        add_tier(admin, 2, 375, 80, 500, 10_000_000, 7_000_000);
        add_tier(admin, 3, 500, 70,  750, 1_000_000, 500_000);
        add_tier(admin, 4, 750, 60, 1000, 600_000, 250_000);
        add_tier(admin, 5, 1000, 50, 1500, 250_000, 100_000);

        allow_coin<BaseEthereum>(admin, 1, 1, utf8(b"Base"));
        allow_coin<BaseUSDC>(admin, 0, 47,  utf8(b"Base"));

        allow_coin<SuiEthereum>(admin, 1, 1,  utf8(b"Sui"));
        allow_coin<SuiUSDC>(admin, 0, 47, utf8(b"Sui"));
        allow_coin<SuiUSDT>(admin, 0, 47, utf8(b"Sui"));
        allow_coin<SuiSui>(admin, 2, 90, utf8(b"Sui"));
        allow_coin<SuiBitcoin>(admin, 1, 0, utf8(b"Sui"));

        allow_coin<SupraCoin>(admin, 3, 500, utf8(b"Supra"));
    }


// === ENTRY FUNCTIONS === //
    public entry fun allow_coin<T>(admin: &signer, tier_id: u8, oracleID: u32, chain: String) acquires Tokens{
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(signer::address_of(admin));
        assert!(!vector::contains(&vault_list.list,&Metadata { tier: tier_id, resource: type_info::type_name<T>(), price: 0, denom: 0, oracleID: oracleID, decimals: get_coin_decimals<T>(), chain: chain }), ERROR_COIN_ALREADY_ALLOWED);
            
        vector::push_back(&mut vault_list.list, Metadata { tier: tier_id, resource: type_info::type_name<T>(), price: 0, denom: 0, oracleID: oracleID, decimals: get_coin_decimals<T>(), chain: chain });
    }

    public entry fun change_coin_oracle<T>(admin: &signer, oracleID: u32) acquires Tokens {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(signer::address_of(admin));
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

    public entry fun change_coin_tier<T>(admin: &signer, tier: u8) acquires Tokens{
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(@dev);
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

    public entry fun add_tier(admin: &signer, tier_id: u8, apr_increase: u16, lend_ratio: u16, minimal_w_fee: u16, deposit_limit: u128, borrow_limit: u128) acquires Tiers{
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let tiers = borrow_global_mut<Tiers>(signer::address_of(admin));

        if (table::contains(&tiers.table, tier_id)) {
            abort ERROR_TIER_ALREADY_EXISTS;
        };

        let tier = Tier { apr_increase, lend_ratio, minimal_w_fee, deposit_limit, borrow_limit };
        table::add(&mut tiers.table, tier_id, tier);
    }

    public entry fun update_tier(admin: &signer, tier_id: u8, apr_increase: u16, lend_ratio: u16, minimal_w_fee: u16, deposit_limit: u128, borrow_limit: u128) acquires Tiers {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let tiers = borrow_global_mut<Tiers>(signer::address_of(admin));

        if (!table::contains(&tiers.table, tier_id)) {
            abort 11;
        };

        let tier_ref = table::borrow_mut(&mut tiers.table, tier_id);
        tier_ref.apr_increase = apr_increase;
        tier_ref.lend_ratio = lend_ratio;
        tier_ref.minimal_w_fee = minimal_w_fee;
        tier_ref.deposit_limit = deposit_limit;
        tier_ref.borrow_limit = borrow_limit;
    }

// === VIEW FUNCTIONS === //
    // === GET TIER DATA  === //
        #[view]
        public fun get_tier(tier_id: u8): Tier acquires Tiers {
            let tiers = borrow_global<Tiers>(@dev);
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

        public fun borrow_scale(tier_id: u8): u16 {
            storage::expect_u16(storage::viewConstant(utf8(b"QiaraVerifiedTokens"), utf8(b"SCALE"))) - (storage::expect_u16(storage::viewConstant(utf8(b"QiaraVerifiedTokens"), utf8(b"BORROW_SCALE")))*(tier_id as u16))
        }

        public fun lend_scale(tier_id: u8): u16 {
            storage::expect_u16(storage::viewConstant(utf8(b"QiaraVerifiedTokens"), utf8(b"SCALE"))) - (storage::expect_u16(storage::viewConstant(utf8(b"QiaraVerifiedTokens"), utf8(b"LEND_SCALE")))*(tier_id as u16))
        }

        public fun deposit_limit(tier_id: u8): u128 acquires Tiers{
            let tier = get_tier(tier_id);
            tier.deposit_limit
        }

        public fun borrow_limit(tier_id: u8): u128 acquires Tiers{
            let tier = get_tier(tier_id);
            tier.borrow_limit
        }


    // === GET COIN DATA === //
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

    // === GET COIN METADATA === //

        #[view]
        public fun get_registered_vaults(): vector<Metadata> acquires Tokens {
            let vault_list = borrow_global<Tokens>(@dev);
            vault_list.list
        }

        #[view]
        public fun get_coin_metadata<T>(): Metadata acquires Tokens {
            let vault_list = borrow_global_mut<Tokens>(@dev);
            let len = vector::length(&vault_list.list);

            while (len > 0) {
                let metadat = vector::borrow(&vault_list.list, len - 1);
                if (metadat.resource == type_info::type_name<T>()) {
                    let (price, price_decimals, _, _) = supra_oracle_storage::get_price(get_coin_metadata_oracle(metadat));
                    let denom = Math::pow10_u256((price_decimals as u8));
                    return Metadata { 
                        tier: metadat.tier, 
                        resource: metadat.resource, 
                        price: price, 
                        denom: denom, 
                        oracleID: metadat.oracleID, 
                        decimals: metadat.decimals, 
                        chain: metadat.chain
                    };
                };
                len = len - 1;
            };

            abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
        }


        public fun get_coin_metadata_tier(metadata: &Metadata): u8 {
            metadata.tier
        }

        public fun get_coin_metadata_resource(metadata: &Metadata): String {
            metadata.resource
        }

        public fun get_coin_metadata_price(metadata: &Metadata): u128 {
            metadata.price
        }

        public fun get_coin_metadata_denom(metadata: &Metadata): u256 {
            metadata.denom
        }

        public fun get_coin_metadata_oracle(metadata: &Metadata): u32 {
            metadata.oracleID
        }

        public fun get_coin_metadata_decimals(metadata: &Metadata): u8 {
            metadata.decimals
        }

        #[view]
        public fun get_coin_metadata_by_res(res: String): Metadata acquires Tokens {
            let vault_list = borrow_global_mut<Tokens>(@dev);
            let len = vector::length(&vault_list.list);

            while (len > 0) {
                let metadat = vector::borrow(&vault_list.list, len - 1);
                if (metadat.resource == res) {
                    let (price, price_decimals, _, _) = supra_oracle_storage::get_price(get_coin_metadata_oracle(metadat));
                    let denom = Math::pow10_u256((price_decimals as u8));
                    return Metadata { 
                        tier: metadat.tier, 
                        resource: metadat.resource, 
                        price: price, 
                        denom: denom, 
                        oracleID: metadat.oracleID, 
                        decimals: metadat.decimals, 
                        chain: metadat.chain
                    };
                };
                len = len - 1;
            };

            abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
        }
}
