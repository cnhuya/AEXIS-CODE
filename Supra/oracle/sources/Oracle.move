module dev::QiaraOracleV1 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use std::signer;
    use supra_oracle::supra_oracle_storage;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_TOKEN_PRICE_COULDNT_BE_FOUND: u64 = 1;
    
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

// === STRUCTS === //
    struct Prices has copy, key{
        map: Map<String, u256>,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Prices>(@dev)) {
            move_to(admin, Prices { map: map::new<String, u256>() });
        };
    }

    public fun impact_price(name: String, oracleID: u64, impact: u256, isPositive: bool, perm: Permission) acquires Prices{

        let price = ensure_price(borrow_global_mut<Prices>(@dev), name, oracleID);

        if (isPositive){
            *price = *price + impact;
        } else {
            *price = *price - impact
        }


    }

    fun ensure_price(prices: &mut Prices, name: String, oracleID: u64): &mut u256{
        if (!map::contains_key(&prices.map, &name)) {

            let (price, price_decimals, _, _) = supra_oracle_storage::get_price((oracleID as u32));

            map::upsert(&mut prices.map, name, (price as u256));
        };
        return map::borrow_mut(&mut prices.map, &name)
    }



    #[view]
    public fun calculate_price_impact_penalty_spot(token:String,penalty_deductor: u256, hours: u256, value: u256, liquidity: u256): (u256,u256) acquires Tokens{
        let base_penalty = 100*100_000_000;

        let valueUSD = getValue(token, value*1000000000000000000);
        let liquidityUSD = getValue(token, liquidity*1000000000000000000);

        let penalty = 0;
        if((hours)*(hours)*(penalty_deductor) < base_penalty){
            penalty = base_penalty-((hours)*(hours)*(penalty_deductor));
        };

        let valued_price_impact_penalty = (valueUSD*1_000_000  / liquidityUSD)*penalty; // percentage
        let impact_percentage = (valueUSD*10000000000000000 / liquidityUSD)-valued_price_impact_penalty;
        let current_price = oracle::viewPrice(token);
        let impact = impact_percentage*current_price;

        return ((impact/10_000_000_000_000_000)impact_percentage)
    }

    #[view]
    public fun calculate_price_impact_perp(token: String, liquidity: u256, value: u256): (u256,u256) acquires Tokens{

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
    public fun viewAllPrices(name: String): Map<String, u256> acquires Prices{

        borrow_global_mut<Prices>(@dev).map

    }

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices{

        let prices = borrow_global_mut<Prices>(@dev);

        if (!map::contains_key(&prices.map, &name)) {
            abort(ERROR_TOKEN_PRICE_COULDNT_BE_FOUND)
        };

        return *map::borrow(&prices.map, &name)

    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices{

        let prices = borrow_global_mut<Prices>(@dev);

        if (!map::contains_key(&prices.map, &name)) {
            return false
        };

        return true

    }
}
