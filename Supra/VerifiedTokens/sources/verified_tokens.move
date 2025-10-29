module dev::QiaraVerifiedTokensV40{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use std::option::{Option};
    use supra_oracle::supra_oracle_storage;
    use supra_framework::coin;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use std::timestamp;

    use dev::QiaraStorageV29::{Self as storage};
    use dev::QiaraMathV9::{Self as Math};
    use dev::QiaraCoinTypesV11::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use dev::QiaraVaultRatesV11::{Self as VaultRates};


    use dev::QiaraTiersV26::{Self as tier};
    use dev::QiaraFeeVaultV6::{Self as fee};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST: u64 = 2;
    const ERROR_TIER_ALREADY_EXISTS: u64 = 3;
    const ERROR_COIN_ALREADY_ALLOWED: u64 = 4;
    const ERROR_TIER_NOT_FOUND: u64 = 5;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

// === STRUCTS === //
    struct Tokens has key, store, copy{
        list: vector<Metadata>,
    }

    struct Metadata has key, store, copy,drop{
        resource: String,
        chain: String,
        tier:u8,
        decimals: u8,
        oracleID: u32,
        offchainID: u32,
        creation: u64,
        listed: u64,
        penalty_expiry: u64,
        credit: u256,
        tokenomics: Tokenomics,
    }

    struct VMetadata has key, store, copy, drop {
        resource: String,
        chain: String,
        tier:u8,
        decimals: u8,
        oracleID: u32,
        offchainID: u32,
        creation: u64,
        listed: u64,
        penalty_expiry: u64,
        credit: u256,
        price: Price,
        market: Market,
        tokenomics: Tokenomics,
        full_tier: Tier,
    }

    struct Tier has key, store, copy,drop {
        tierName: String,
        efficiency: u64,
        multiplier: u64,
    }

    struct Tokenomics has key, copy, store, drop {
        max_supply: u128,
        circulating_supply: u128,
        total_supply: u128,
    }

    struct Market has key, copy,store, drop {
        mc: u128,
        fdv: u128,
        fdv_mc: u128,
    }

    struct Price has key, copy,store, drop {
        price: u128,
        denom: u128,
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
    fun init_module(admin: &signer) acquires Tokens{
        let deploy_addr = signer::address_of(admin);

        if (!exists<Tokens>(deploy_addr)) {
            move_to(admin, Tokens { list: vector::empty<Metadata>() });
        };
    //tttta(11111111);
    create_info<SupraCoin>(admin, utf8(b"Supra"), 1732598400, 1, 500, 100_000_000_000, 19_713_700_000, 80_508_180_397, 1);
    //tttta(11111111);
    create_info<SuiBitcoin>(admin, utf8(b"Sui"), 1231006505, 1, 0, 21000000, 19_941_253, 19_941_253, 1);
    create_info<SuiEthereum>(admin, utf8(b"Sui"), 1438269983, 1, 1, 120_698_129, 120_698_129, 120_698_129, 1);
    create_info<SuiSui>(admin, utf8(b"Sui"), 1683062400, 1, 90, 10_000_000_000, 3_625_742_933, 10_000_000_000, 1);
    
    create_info<SuiUSDC>(admin, utf8(b"Sui"), 0, 1, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 0);
    create_info<SuiUSDT>(admin, utf8(b"Sui"), 0, 1, 47, 185_977_352_465, 185_977_352_465, 185_977_352_465, 0);
    create_info<BaseEthereum>(admin, utf8(b"Base"), 1438269983, 1, 1, 120_698_129, 120_698_129, 120_698_129, 1);
    create_info<BaseUSDC>(admin, utf8(b"Base"), 0, 1, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 0);
    //tttta(11111111);
   // create_info<SupraCoin>(admin, utf8(b"Supra"), 1732598400, 1, 500, 100_000_000_000, 19_713_700_000, 80_508_180_397, false);
   // tttta(11111111);
    }

// === ENTRY FUNCTIONS === //

    fun tttta(id: u64){
        abort(id);
    }

    public entry fun create_info<Token>(admin: &signer, chain: String, creation: u64, offchainID: u32, oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8) acquires Tokens {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(signer::address_of(admin));

        let tokenomics = Tokenomics { max_supply: max_supply, circulating_supply: circulating_supply, total_supply: total_supply };
        //tttta(999999);
        let (calculated_credit, _, _, _, _) = calculate_asset_credit(&tokenomics, creation, oracleID);
        //tttta(999999);
        let tier_id = associate_tier(calculated_credit, stable);
        //tttta((tier_id as u64)); 0x1
        let metadata = Metadata {resource: type_info::type_name<Token>(), chain: chain, tier: tier_id,  decimals: get_coin_decimals<Token>(), oracleID: oracleID, offchainID: offchainID, creation: creation, listed:timestamp::now_seconds(), penalty_expiry: timestamp::now_seconds() + storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_PENALTY_TIME"))), credit: calculated_credit, tokenomics: tokenomics };

        assert!(!vector::contains(&vault_list.list,&metadata), ERROR_COIN_ALREADY_ALLOWED);
        vector::push_back(&mut vault_list.list, metadata);
        fee::init_fee_vault<Token>(admin);
        //tttta((tier_id as u64)); 0x1
    }

    public entry fun update_tokenomics<Token>(admin: &signer, max_supply: u128, circulating_supply: u128, total_supply: u128) acquires Tokens {

        let tokenomics = Tokenomics { max_supply: max_supply, circulating_supply: circulating_supply, total_supply: total_supply };


        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);


        let vault_list = borrow_global_mut<Tokens>(@dev);
        let len = vector::length(&vault_list.list);

        while (len > 0) {
            let metadat = vector::borrow_mut(&mut vault_list.list, len - 1);
            if (metadat.resource == type_info::type_name<Token>()) {
                metadat.tokenomics = tokenomics;
                return;
            };
            len = len - 1;
        };

        abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)

    }

    public entry fun update_offchainID<Token>(admin: &signer, offchainID: u32) acquires Tokens {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);


        let vault_list = borrow_global_mut<Tokens>(@dev);
        let len = vector::length(&vault_list.list);

        while (len > 0) {
            let metadat = vector::borrow_mut(&mut vault_list.list, len - 1);
            if (metadat.resource == type_info::type_name<Token>()) {
                metadat.offchainID = offchainID;
                return;
            };
            len = len - 1;
        };

        abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
    }

    public entry fun update_oracleID<Token>(admin: &signer, oracleID: u32) acquires Tokens {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(@dev);
        let len = vector::length(&vault_list.list);

        while (len > 0) {
            let metadat = vector::borrow_mut(&mut vault_list.list, len - 1);
            if (metadat.resource == type_info::type_name<Token>()) {
                metadat.oracleID = oracleID;
                return;
            };
            len = len - 1;
        };

        abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)

    }

// === HELPER FUNCTIONS === //


    fun calculate_market(info: &Metadata): Market {
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(info.oracleID);
        let denom = Math::pow10_u256((price_decimals as u8));
        let mc = (info.tokenomics.circulating_supply as u128) * price / (denom as u128);
        let fdv = (info.tokenomics.max_supply as u128) * price / (denom as u128);
        let fdv_mc = if (mc > 0) { (fdv * 100) / mc } else { 0 };
        Market { mc: mc, fdv: fdv, fdv_mc: fdv_mc }
    }

fun calculate_asset_credit(
    tokenomics: &Tokenomics,
    creation: u64,
    oracleID: u32
): (u256, u256, u256, u256, u256) {


    let now = timestamp::now_seconds();
    let months: u64 = 0;

    if (now > creation && now - creation >= 2629743) {
        months = (now - creation) / 2629743;
    };

    let (price, price_decimals, _, _) = supra_oracle_storage::get_price(oracleID);
    let denom_u256 = Math::pow10_u256((price_decimals as u8));


    let denom = (denom_u256 as u256);

    let mc: u256 = (tokenomics.circulating_supply as u256) * (price as u256) / denom;
    let fdv: u256 = (tokenomics.max_supply as u256) * (price as u256) / denom;
    //tttta((mc as u64)) 0x1c64b47;
    let months_u128 = (months as u256);
    let x: u256 = ((mc + mc) + (mc*(months_u128/2))) - (fdv / 2);

    //tttta((months_u128 as u64)); //0x2
    let result: u256 = (mc + x) * (months_u128 / 2);
    //tttta((result as u64)); 0x1f9feb1242010
    (x, mc, fdv, (creation as u256), x)
}


    fun associate_tier(credit: u256, stable: u8): u8{

        if(stable == 0){
            return 0
        };

        if(stable == 00){
            return 00
        };


        if (credit >= 25_000_000_000){
            return 1
        } else if (credit >= 7_500_000_000){
            return 2
        } else if (credit >= 2_500_000_000){
            return 3
        } else if (credit >= 1_000_000_000){
            return 4
        } else if (credit >= 500_000_000){
            return 5
        } else if (credit >= 250_000_000){
            return 6
        } else {
            return 7
        }
    }





// === VIEW FUNCTIONS === //
    // === GET COIN DATA === //
        #[view]
        public fun get_coin_data<Token>(): CoinData {
            let type = type_info::type_name<Token>();
            CoinData { resource: type, name: coin::name<Token>(), symbol: coin::symbol<Token>(), decimals: coin::decimals<Token>(), supply: coin::supply<Token>() }
        }

        public fun get_coin_type<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.resource
        }

        public fun get_coin_name<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.name
        }

        public fun get_coin_symbol<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.symbol
        }

        public fun get_coin_decimals<Token>(): u8 {
            let coin_data = get_coin_data<Token>();
            coin_data.decimals
        }

        public fun get_coin_supply<Token>(): Option<u128> {
            let coin_data = get_coin_data<Token>();
            coin_data.supply
        }

        public fun get_coin_chain<Token>(): Option<u128> {
            let coin_data = get_coin_data<Token>();
            coin_data.supply
        }

    // === GET COIN METADATA === //

        #[view]
        public fun get_registered_vaults(): vector<Metadata> acquires Tokens {
            let vault_list = borrow_global<Tokens>(@dev);
            vault_list.list
        }

        #[view]
        public fun get_coin_metadata<Token>(): VMetadata acquires Tokens {
            let vault_list = borrow_global_mut<Tokens>(@dev);
            let len = vector::length(&vault_list.list);
            let i = 0;
            while (i < len) {
                let metadat = vector::borrow(&vault_list.list, i);
                if (metadat.resource == type_info::type_name<Token>()) {
                    let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadat.oracleID);
                    let denom = Math::pow10_u256((price_decimals as u8));

                    let tier;

                    if(metadat.penalty_expiry > timestamp::now_seconds()){
                        tier = Tier { tierName: tier::convert_tier_to_string(metadat.tier), 
                        efficiency: ((tier::tier_efficiency(metadat.tier)*100) / storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_EFFICIENCY_HANDICAP")))),
                        multiplier: (tier::tier_multiplier(metadat.tier) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_MULTIPLIER_HANDICAP")))/100 )
                        } ;
                    } else {
                        tier = Tier { tierName: tier::convert_tier_to_string(metadat.tier), efficiency: tier::tier_efficiency(metadat.tier), multiplier: tier::tier_multiplier(metadat.tier) };
                    };


                    return VMetadata { 
                        resource: metadat.resource,
                        chain: metadat.chain,
                        tier: metadat.tier,
                        decimals: metadat.decimals, 
                        oracleID: metadat.oracleID, 
                        offchainID: metadat.offchainID,
                        creation: metadat.creation,
                        listed: metadat.listed,
                        penalty_expiry: metadat.penalty_expiry,
                        credit: metadat.credit,
                        price: Price { price: price, denom: (denom as u128) },
                        market: calculate_market(metadat),
                        tokenomics: metadat.tokenomics,
                        full_tier: tier,
                    };
                };
                i = i + 1;
            };

            abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
        }


        public fun get_coin_metadata_resource(metadata: &VMetadata): String {
            metadata.resource
        }

        public fun get_coin_metadata_chain(metadata: &VMetadata): String {
            metadata.chain
        }

        public fun get_coin_metadata_tier(metadata: &VMetadata): u8 {
            metadata.tier
        }

        public fun get_coin_metadata_decimals(metadata: &VMetadata): u8 {
            metadata.decimals
        }

        public fun get_coin_metadata_oracleID(metadata: &VMetadata): u32 {
            metadata.oracleID
        }

        public fun get_coin_metadata_offchainID(metadata: &VMetadata): u32 {
            metadata.offchainID
        }

        public fun get_coin_metadata_creation(metadata: &VMetadata): u64 {
            metadata.creation
        }

        public fun get_coin_metadata_credit(metadata: &VMetadata): u256 {
            metadata.credit
        }

    // PRICE
        public fun get_coin_metadata_full_price(metadata: &VMetadata): Price {
            metadata.price
        }

        public fun get_coin_metadata_price(metadata: &VMetadata): u256 {
            (metadata.price.price as u256)
        }

        public fun get_coin_metadata_denom(metadata: &VMetadata): u256 {
            (metadata.price.denom as u256)
        }

    // MARKET
        public fun get_coin_metadata_market(metadata: &VMetadata): Market {
            metadata.market
        }

        public fun get_coin_metadata_fdv(metadata: &VMetadata): u128 {
            metadata.market.fdv
        }

        public fun get_coin_metadata_mc(metadata: &VMetadata): u128 {
            metadata.market.mc
        }

        public fun get_coin_metadata_fdv_mc(metadata: &VMetadata): u128 {
            metadata.market.fdv_mc
        }

    // TOKENOMICS
        public fun get_coin_metadata_tokenomics(metadata: &VMetadata): Tokenomics {
            metadata.tokenomics
        }

        public fun get_coin_metadata_circulating_supply(metadata: &VMetadata): u128 {
            metadata.tokenomics.circulating_supply
        }

        public fun get_coin_metadata_max_supply(metadata: &VMetadata): u128 {
            metadata.tokenomics.max_supply
        }

        public fun get_coin_metadata_total_supply(metadata: &VMetadata): u128 {
            metadata.tokenomics.total_supply
        }


    // TIER
        public fun get_coin_metadata_full_tier(metadata: &VMetadata): Tier {
            metadata.full_tier
        }

        public fun get_coin_metadata_tier_name(metadata: &VMetadata): String {
            metadata.full_tier.tierName
        }

        public fun get_coin_metadata_tier_efficiency(metadata: &VMetadata): u64 {
            metadata.full_tier.efficiency
        }

        public fun get_coin_metadata_full_multiplier(metadata: &VMetadata): u64 {
            metadata.full_tier.multiplier
        }

    // OFF STRUCTS HELPERS
        public fun get_coin_metadata_rate_scale(metadata: &VMetadata, isLending: bool): u64 {
            let x = 0;
            if(isLending) { x = 200 };

            if(metadata.tier == 1){
                return storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - x
            };
    
           storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - ((metadata.tier as u64)*500u64) - x
        }

        public fun get_coin_metadata_min_lend_apr(metadata: &VMetadata): u64 {
            storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MIN_LEND_APR_FACTOR"))) + (metadata.full_tier.multiplier * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MIN_LEND_APR_FACTOR"))))/1000
        }

        public fun get_coin_metadata_market_rate(metadata: &VMetadata): u64 {
            
            let min_rate = get_coin_metadata_min_lend_apr(metadata);
            let rate_scale = (VaultRates::get_vault_lend_rate(VaultRates::get_vault_rate(metadata.resource)) as u64);
            
            min_rate + rate_scale
        }

        #[view]
        public fun get_coin_metadata_by_res(res: String): VMetadata acquires Tokens {
            let vault_list = borrow_global_mut<Tokens>(@dev);
            let len = vector::length(&vault_list.list);

            while (len > 0) {
                let metadat = vector::borrow(&vault_list.list, len - 1);
                if (metadat.resource == res) {
                    let (price, price_decimals, _, _) = supra_oracle_storage::get_price(metadat.oracleID);
                    let denom = Math::pow10_u256((price_decimals as u8));
                    let tier;

                    if(metadat.penalty_expiry > timestamp::now_seconds()){
                        tier = Tier { tierName: tier::convert_tier_to_string(metadat.tier), 
                        efficiency: ((tier::tier_efficiency(metadat.tier)*100) / storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_EFFICIENCY_HANDICAP")))),
                        multiplier: (tier::tier_multiplier(metadat.tier) * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_MULTIPLIER_HANDICAP")))/100 )
                        } ;
                    } else {
                        tier = Tier { tierName: tier::convert_tier_to_string(metadat.tier), efficiency: tier::tier_efficiency(metadat.tier), multiplier: tier::tier_multiplier(metadat.tier) };
                    };

                    return VMetadata { 
                        resource: metadat.resource,
                        chain: metadat.chain,
                        tier: metadat.tier,
                        decimals: metadat.decimals, 
                        oracleID: metadat.oracleID, 
                        offchainID: metadat.offchainID,
                        creation: metadat.creation,
                        listed: metadat.listed,
                        penalty_expiry: metadat.penalty_expiry,
                        credit: metadat.credit,
                        price: Price { price: price, denom: (denom as u128) },
                        market: calculate_market(metadat),
                        tokenomics: metadat.tokenomics,
                        full_tier: tier,
                    };
                };
                len = len - 1;
            };

            abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
        }
}
