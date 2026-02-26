module dev::QiaraTokensMetadataV4{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use std::timestamp;
    use supra_framework::event;

    use dev::QiaraStorageV1::{Self as storage};
    use dev::QiaraMathV1::{Self as Math};

    use dev::QiaraTokensRatesV4::{Self as rates};
    use dev::QiaraTokensTiersV4::{Self as tier};

    use dev::QiaraOracleV1::{Self as oracle, Access as OracleAccess};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST: u64 = 2;
    const ERROR_TIER_ALREADY_EXISTS: u64 = 3;
    const ERROR_COIN_ALREADY_ALLOWED: u64 = 4;
    const ERROR_TIER_NOT_FOUND: u64 = 5;
    const ERROR_SIZE_TOO_BIG_COMAPRED_TO_DV: u64 = 6;
    const ERROR_MINIMUM_VALUE_NOT_MET: u64 = 7;

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
    // Registry of all listed chains and supported tokens on that chain
    //struct Registry has key, store, copy{
    //    list: Map<String, vector<String>>,
   // }

    struct Permissions has key {
        oracle_access: OracleAccess,
    }

    struct Tokens has key, store, copy{
        list: vector<Metadata>,
    }

    struct Metadata has key, store, copy,drop{
        symbol: String,
        tier:u8,
        decimals: u8,
        oracleID: u32,
        creation: u64,
        listed: u64,
        penalty_expiry: u64,
        credit: u256,
        tokenomics: Tokenomics,
    }

    struct VMetadata has key, store, copy, drop {
        symbol: String,
        tier:u8,
        decimals: u8,
        oracleID: u32,
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


// === EVENTS === //
    #[event]
    struct MetadataChange has copy, drop, store {
        address: address,
        asset: String,
        tier: Tier,
        tokenomics: Tokenomics,
        market: Market,
        price: Price,
        time: u64
    }

// === INIT === //
    fun init_module(admin: &signer){
        let deploy_addr = signer::address_of(admin);

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { oracle_access: oracle::give_access(admin)});
        };

        if (!exists<Tokens>(deploy_addr)) {
            move_to(admin, Tokens { list: vector::empty<Metadata>() });
        };

    }

// === ENTRY FUNCTIONS === //

    public entry fun create_metadata(admin: &signer, symbol: String, creation: u64,oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8) acquires Tokens {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

//        let tokens_registry = borrow_global_mut<Registry>(@dev);

//        if (!map::contains_key(&tokens_registry.registry, &symbol)) {
//            map::upsert(&mut tokens_registry.registry, symbol, vector::empty<String>());
//        };

//        let c = map::borrow_mut(&mut tokens_registry.registry, &symbol);
//        if (!vector::contains(c, &chain_type)) {
//            vector::push_back(c, chain_type);
 //       };

        let vault_list = borrow_global_mut<Tokens>(signer::address_of(admin));

        let tokenomics = Tokenomics { max_supply: max_supply, circulating_supply: circulating_supply, total_supply: total_supply };

        let (calculated_credit, _, _, _, _) = calculate_asset_credit(&tokenomics, creation, oracleID);

        let tier_id = associate_tier(calculated_credit, stable);

        let metadata = Metadata {symbol:symbol, tier: tier_id,  decimals: 8, oracleID: oracleID, creation: creation, listed:timestamp::now_seconds(), penalty_expiry: timestamp::now_seconds() + storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_PENALTY_TIME"))), credit: calculated_credit, tokenomics: tokenomics };

        assert!(!vector::contains(&vault_list.list,&metadata), ERROR_COIN_ALREADY_ALLOWED);
        vector::push_back(&mut vault_list.list, metadata);
    }

    public entry fun update_tokenomics(admin: &signer, symbol: String, max_supply: u128, circulating_supply: u128, total_supply: u128) acquires Tokens {

        let tokenomics = Tokenomics { max_supply: max_supply, circulating_supply: circulating_supply, total_supply: total_supply };

        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(@dev);
        let len = vector::length(&vault_list.list);

        while (len > 0) {
            let index = len - 1;
            {
                let metadat = vector::borrow_mut(&mut vault_list.list, index);
                if (metadat.symbol == symbol) {
                    metadat.tokenomics = tokenomics;

                    if(metadat.tier == 255 || metadat.tier == 254){
                        return;
                    };

                    let (calculated_credit, _, _, _, _) = calculate_asset_credit(&tokenomics, metadat.creation, metadat.oracleID);
                    metadat.credit = calculated_credit;
                    metadat.tier = associate_tier(calculated_credit, metadat.tier);
                } else {
                    len = len - 1;
                    continue;
                };
            }; 
            
            let metadat_immutable = vector::borrow(&vault_list.list, index);
            let resource_name = metadat_immutable.symbol;
            let m = get_coin_metadata_by_symbol(resource_name);
            let current_tier = get_coin_metadata_full_tier(&m);
            let current_market = get_coin_metadata_market(&m);
            let current_price = get_coin_metadata_full_price(&m);
            
            event::emit(MetadataChange {
                address: signer::address_of(admin),
                asset: resource_name,
                tier: current_tier,
                tokenomics: tokenomics,
                market: current_market,
                price: current_price,
                time: timestamp::now_seconds()
            });

            return;
        };
        abort(ERROR_COIN_RESOURCE_NOT_FOUND_IN_LIST)
    }


    public entry fun update_oracleID(admin: &signer, symbol: String, oracleID: u32) acquires Tokens {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let vault_list = borrow_global_mut<Tokens>(@dev);
        let len = vector::length(&vault_list.list);

        while (len > 0) {
            let metadat = vector::borrow_mut(&mut vault_list.list, len - 1);
            if (metadat.symbol == symbol) {
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

    fun calculate_asset_credit(tokenomics: &Tokenomics,creation: u64,oracleID: u32): (u256, u256, u256, u256, u256) {
        let now = timestamp::now_seconds();
        let days: u64 = 0;

        if (now > creation && now - creation >= 86400 ) {
            days = (now - creation) / 86400 ;
        };

        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(oracleID);
        let denom_u256 = Math::pow10_u256((price_decimals as u8));


        let denom = (denom_u256 as u256);

        let mc: u256 = (tokenomics.circulating_supply as u256) * (price as u256) / denom;
        let fdv: u256 = (tokenomics.max_supply as u256) * (price as u256) / denom;
        let days_u128 = (days as u256);
        if(fdv*2>(mc + mc) + (mc*(days_u128))){
            return (0, mc, fdv, (creation as u256), 0);
        };
        let x: u256 = ((mc + mc) + (mc*(days_u128))) - (fdv*2);

        (x, mc, fdv, (creation as u256), x)
    }


    // deprecated
    #[view]
    public fun calculate_price_impact_penalty_final(token:String,penalty_deductor: u256, hours: u256, valueUSD: u256, liquidityUSD: u256): u256{
        let base_penalty = 100*100_000_000;

        let penalty = 0;
        if((hours)*(hours)*(penalty_deductor) < base_penalty){
            penalty = base_penalty-((hours)*(hours)*(penalty_deductor));
        };

        let valued_price_impact_penalty = (valueUSD*1_000_000  / liquidityUSD)*penalty;
        let impact_percentage = (valueUSD*100_000_000*100_000_000  / liquidityUSD)-valued_price_impact_penalty;
        //impact = impact_percentage*current_price;

        let current_price = oracle::viewPrice(token);
        let impact = (current_price * impact_percentage)/10000000000000000;
        // 3999300000000000 40%
        // 2520000000000000 = 25,2%
        return impact
    }
    // deprecated
    #[view]
    public fun calculate_price_impact_penalty_final2(token:String,penalty_deductor: u256, hours: u256, value: u256, liquidity: u256): (u256,u256,u256,u256,u256,u256) acquires Tokens{
        let base_penalty = 100*100_000_000;

        let valueUSD = getValue(token, value*1000000000000000000);
        let liquidityUSD = getValue(token, liquidity*1000000000000000000);

        let penalty = 0;
        if((hours)*(hours)*(penalty_deductor) < base_penalty){
            penalty = base_penalty-((hours)*(hours)*(penalty_deductor));
        };

        // (2814400000000000000000*1000000)/7036000000000000000000)*400000 = 160000000000 
        let valued_price_impact_penalty = (valueUSD*1_000_000  / liquidityUSD)*penalty; // percentage
        let impact_percentage = (valueUSD*10000000000000000 / liquidityUSD)-valued_price_impact_penalty;
        let current_price = oracle::viewPrice(token);
        let impact = impact_percentage*current_price;

       // let impact = (current_price * impact_percentage)/10000000000000000;
        // 3999300000000000 40%
        // 2520000000000000 = 25,2%
        return ((impact/10_000_000_000_000_000), valueUSD, liquidityUSD, penalty, valued_price_impact_penalty, impact_percentage)
    }

    //2982010000000000000000000000000000
    //359923027659000000000000000000000000

    // deprecated
    #[view]
    public fun calculate_price_impact_second_new2(token: String, liquidity: u256, value: u256): (u256,u256,u256,u256,u256,u256,u256) acquires Tokens{

        let metadata = get_coin_metadata_by_symbol(token);
        let valueUSD = getValue(token, value*1000000000000000000);
        let liquidityUSD = getValue(token, liquidity*1000000000000000000);
        let fdvUSD = ((get_coin_metadata_fdv(&metadata) as u256)*1000000000000000000*1_000_000000);

        let price = getValue(token, 1*1000000000000000000);

        assert!(valueUSD  < fdvUSD/10, ERROR_SIZE_TOO_BIG_COMAPRED_TO_DV); // essentially Value cant be higher than 10% of FDV
        assert!(valueUSD/1_000_000 >= 1000000000000000000, ERROR_MINIMUM_VALUE_NOT_MET); // essentially Value cant be higher than 10% of FDV

        let denominator = ((fdvUSD / 10) - valueUSD + (liquidityUSD * 2) - valueUSD);

        //(1402450*100_000_000_000_000)/1402449997195100

        // Standardize the result to 6 decimal places (1,000,000 = 100%)
        let impact = ((valueUSD * 1000000000000000000) / denominator);
        return (impact,valueUSD, liquidityUSD, fdvUSD, price,(price*impact),denominator)
    }
    // deprecated
    #[view]
    public fun calculate_price_impact_final(token: String, liquidity: u256, value: u256): u256 acquires Tokens{

        let metadata = get_coin_metadata_by_symbol(token);
        let valueUSD = getValue(token, value*1000000000000000000);
        let liquidityUSD = getValue(token, liquidity*1000000000000000000);
        let fdvUSD = ((get_coin_metadata_fdv(&metadata) as u256)*1000000000000000000*1_000_000);

        let price = getValue(token, 1*1000000000000000000);

        assert!(valueUSD < fdvUSD/10, ERROR_SIZE_TOO_BIG_COMAPRED_TO_DV); // essentially Value cant be higher than 10% of FDV
        assert!(valueUSD/1_000_000 >= 1000000000000000000, ERROR_MINIMUM_VALUE_NOT_MET); // essentially Value cant be higher than 10% of FDV

        let denominator = ((fdvUSD / 10) - valueUSD + (liquidityUSD * 2) - valueUSD);

        //(1402450*100_000_000_000_000)/1402449997195100

        // Standardize the result to 6 decimal places (1,000,000 = 100%)
        let impact = ((valueUSD * 1000000000000000000) / denominator);
        return (price*impact)/1000000000000000000
    }

    #[view]
    public fun calculate_price_impact_spot(token:String,penalty_deductor: u256, hours: u256, value: u256, liquidity: u256): (u256) acquires Tokens{
        let base_penalty = 100*100_000_000;

        let valueUSD = getValue(token, value*1000000000000000000);
        let liquidityUSD = getValue(token, liquidity*1000000000000000000);

        let penalty = 0;
        if((hours)*(hours)*(penalty_deductor) < base_penalty){
            penalty = base_penalty-((hours)*(hours)*(penalty_deductor));
        };

        let valued_price_impact_penalty = (valueUSD*100_000_000  / liquidityUSD)*penalty; // percentage
        let impact_percentage = (valueUSD*1000000000000000000 / liquidityUSD)-valued_price_impact_penalty;
        let current_price = oracle::viewPrice(token);
        let impact = impact_percentage*current_price;

        //1_000_000_000_000_000_000


        //100000000
        //50000000

        //1_000_000
        return(impact/1_000_000_000_000_000_000)
    }

    #[view]
    public fun calculate_price_impact_perp(token: String, liquidity: u256, value: u256): (u256) acquires Tokens{

        let metadata = get_coin_metadata_by_symbol(token);
        let valueUSD = getValue(token, value*1000000000000000000);
        let liquidityUSD = getValue(token, liquidity*1000000000000000000);
        let fdvUSD = ((get_coin_metadata_fdv(&metadata) as u256)*1000000000000000000*10_000_000);

        let price = getValue(token, 1*1000000000000000000);

        assert!(valueUSD < fdvUSD/10, ERROR_SIZE_TOO_BIG_COMAPRED_TO_DV); // essentially Value cant be higher than 10% of FDV
        assert!(valueUSD >= 1000000000000000000, ERROR_MINIMUM_VALUE_NOT_MET); 

        let denominator = ((fdvUSD / 100) - valueUSD + (liquidityUSD * 2) - valueUSD);

        //(1402450*100_000_000_000_000)/1402449997195100

        // Standardize the result to 6 decimal places (1,000,000 = 100%)
        let impact = ((valueUSD * 1000000000000000000) / denominator);
        return (price*impact)/1_000_000_000_000_000_000
    }



    #[view]
    public fun calculate_impact_fee(token: String, size: u256, fee_percentage: u256): u256{
        //3272526887572493807746-296254759609948020295/3272526887572493807746

        let current_price = oracle::viewPrice(token);
        let valueUSD = size*current_price;

        let fee = (valueUSD*fee_percentage);
        return fee/1000000000000000000

        //32725236150456062352521922540000
    }

    #[view]
    public fun test_impact_view(token: String, size: u256, liquidity: u256, isPositive: bool, type: String): (u256,u256,u256,u256,u256,u256) acquires Permissions, Tokens{

        let metadata = get_coin_metadata_by_symbol(token);
        let oracleID = get_coin_metadata_oracleID(&metadata);
        let tierID = get_coin_metadata_tier(&metadata);

        let vault_listed = get_coin_metadata_listed(&metadata);

        let oracle_native_weight = tier::oracle_native_weight(tierID);
        let percentage_impact = 0;
        // this needs to be done to assure that price exists in map (it sets the price to current price from oracle, which is enough for initialization)
        if(!oracle::existsPrice(token)){
           percentage_impact = oracle::impact_price(token, (oracleID as u64), 0, isPositive, oracle_native_weight, oracle::give_permission(&borrow_global<Permissions>(@dev).oracle_access));            
        };

        let current_price = oracle::viewPrice(token);

        let impact = 0;

        if(type == utf8(b"perps")){
            (impact) = calculate_price_impact_perp(token, liquidity, size);
        } else if (type == utf8(b"spot")){
            (impact) = calculate_price_impact_spot(token,(tier::price_impact_penalty(tierID) as u256),((vault_listed/3600) as u256), size, liquidity);
        };
  
        let fee = percentage_impact*size;
        //oracle::impact_price(token, (oracleID as u64), impact, isPositive, oracle::give_permission(&borrow_global<Permissions>(@dev).oracle_access));            
        return(percentage_impact, current_price, impact,fee,0, (vault_listed as u256))
    }

    public fun impact(token: String, size: u256, liquidity: u256, isPositive: bool, type: String, perm:Permission): (u256,u256) acquires Permissions, Tokens{

        let metadata = get_coin_metadata_by_symbol(token);
        let oracleID = get_coin_metadata_oracleID(&metadata);
        let tierID = get_coin_metadata_tier(&metadata);

        let vault_listed = get_coin_metadata_listed(&metadata);

        let oracle_native_weight = tier::oracle_native_weight(tierID);

        // this needs to be done to assure that price exists in map (it sets the price to current price from oracle, which is enough for initialization)
        if(!oracle::existsPrice(token)){
            oracle::impact_price(token, (oracleID as u64), 0, isPositive, oracle_native_weight, oracle::give_permission(&borrow_global<Permissions>(@dev).oracle_access));            
        };
        let current_price = oracle::viewPrice(token);

        let impact = 0;

        if(type == utf8(b"perps")){
            (impact) = calculate_price_impact_perp(token, liquidity, size);
        } else if (type == utf8(b"spot")){
            (impact) = calculate_price_impact_spot(token,(tier::price_impact_penalty(tierID) as u256),((vault_listed/3600) as u256), size, liquidity);
        };
  
        let percentage_impact = oracle::impact_price(token, (oracleID as u64), impact, isPositive, oracle_native_weight, oracle::give_permission(&borrow_global<Permissions>(@dev).oracle_access));            
        let fee = percentage_impact*size;

        return(percentage_impact, fee)
    }


    fun associate_tier(credit: u256, stable: u8): u8{

        if(stable == 255){
            return 255
        };

        if(stable == 254){
            return 254
        };

        if (credit >= 10000000000000){
            return 1
        } else if (credit >= 1000000000000){
            return 2
        } else if (credit >= 250000000000){
            return 3
        } else if (credit >= 100000000000){
            return 4
        } else if (credit >= 50000000000){
            return 5
        } else if (credit >= 25000000000){
            return 6
        } else {
            return 7
        }
    }

// === VIEW FUNCTIONS === //
    // === GET COIN METADATA === //

        #[view]
        public fun get_registered_vaults(): vector<Metadata> acquires Tokens {
            let vault_list = borrow_global<Tokens>(@dev);
            vault_list.list
        }

        #[view]
        public fun get_coin_metadata(symbol: String): VMetadata acquires Tokens {
            let vault_list = borrow_global_mut<Tokens>(@dev);
            let len = vector::length(&vault_list.list);
            let i = 0;
            while (i < len) {
                let metadat = vector::borrow(&vault_list.list, i);
                if (metadat.symbol == symbol) {
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
                        symbol: metadat.symbol,
                        tier: metadat.tier,
                        decimals: metadat.decimals, 
                        oracleID: metadat.oracleID, 
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


        public fun get_coin_metadata_symbol(metadata: &VMetadata): String {
            metadata.symbol
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

        public fun get_coin_metadata_creation(metadata: &VMetadata): u64 {
            metadata.creation
        }

        public fun get_coin_metadata_listed(metadata: &VMetadata): u64 {
            metadata.listed
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

    // CALCULATIONS
    // gets value by usd
    #[view]
    public fun getValue(symbol: String, amount: u256): u256 acquires Tokens{
        let metadata = get_coin_metadata_by_symbol(symbol);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(get_coin_metadata_oracleID(&metadata));
        return ((amount as u256) * (price as u256)) / get_coin_metadata_denom(&metadata)
    }

    // converts usd back to coin value
    #[view]
    public fun getValueByCoin(symbol: String, amount: u256): u256 acquires Tokens{
        let metadata = get_coin_metadata_by_symbol(symbol);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(get_coin_metadata_oracleID(&metadata));
        return (((amount as u256)* get_coin_metadata_denom(&metadata)) / (price as u256))
    }

    // OFF STRUCTS HELPERS
        #[view]
        public fun t_helper(symbol: String): (u64, u64, u64,u64,u64,u64,u64,u64) acquires Tokens {
            let metadata = get_coin_metadata(symbol);
            (
                get_coin_metadata_rate_scale(&metadata, false),
                get_coin_metadata_rate_scale(&metadata, true),
                0,
               // get_coin_metadata_market_rate(&metadata),
                get_coin_metadata_market_w_fee(&metadata),
                0,0,0,0
            )
        }

        public fun get_coin_metadata_rate_scale(metadata: &VMetadata, isLending: bool): u64 {
            let x = 0;
            if(!isLending) { x = 200 };

            if(metadata.tier == 1){
                return storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - x
            };

            if(metadata.tier == 255){
                return storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - x
            };

            if(metadata.tier == 254){
                return storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - x
            };
    
           storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"))) - ((metadata.tier as u64)*500u64) - x
        }


        public fun get_coin_metadata_market_w_fee(metadata: &VMetadata): u64 {
            
            (metadata.full_tier.multiplier * storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"W_FEE")))) / (storage::expect_u64(storage::viewConstant(utf8(b"QiaraMarket"), utf8(b"NEW_MULTIPLIER_HANDICAP")))/100)
        
        }


        #[view]
        public fun get_coin_metadata_by_symbol(res: String): VMetadata acquires Tokens {
            let vault_list = borrow_global_mut<Tokens>(@dev);
            let len = vector::length(&vault_list.list);

            while (len > 0) {
                let metadat = vector::borrow(&vault_list.list, len - 1);
                if (metadat.symbol == res) {
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
                        symbol: metadat.symbol,
                        tier: metadat.tier,
                        decimals: metadat.decimals, 
                        oracleID: metadat.oracleID, 
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
