module dev::QiaraOracleV1 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use std::signer;
    use std::timestamp;
    use supra_oracle::supra_oracle_storage;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use supra_framework::event;

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

// === EVENTS === //
    #[event]
    struct PriceChangeEvent has copy, drop, store {
        supra_oracle_price: u256,
        old_qiara_oracle_price_impact: Integer, 
        new_qiara_oracle_price_impact: Integer,    
        time: u64
    }

// === STRUCTS === //
    struct Prices has copy, key{
        map: Map<String, Integer>,
    }

    struct Integer has drop, key, store, copy {
        oracleID: u64,
        value: u256,
        isPositive: bool,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Prices>(@dev)) {
            move_to(admin, Prices { map: map::new<String, Integer>() });
        };
    }

public fun impact_price(name: String, oracleID: u64, impact: u256, isPositive: bool, native_oracle_weight: u256, perm: Permission): u256 acquires Prices {

    let prices_storage = borrow_global_mut<Prices>(@dev);
    let price = ensure_price(prices_storage, name, oracleID);
    
    // Capture old state for the event
    let old_price_state = *price;

    let (supra_oracle_price, _, _, _) = supra_oracle_storage::get_price((oracleID as u32));
    
    // Scaling impact
    let scaled_impact = (impact * 1_000_000) / native_oracle_weight;
    if (scaled_impact == 0) { return 0 };

    if (isPositive) {
        if (price.isPositive) {
            price.value = price.value + scaled_impact;
        } else {
            if (scaled_impact >= price.value) {
                price.value = scaled_impact - price.value;
                price.isPositive = true;
            } else {
                price.value = price.value - scaled_impact;
            };
        }
    } else {
        // Handle Negative Impact
        if (price.isPositive) {
            if (scaled_impact >= price.value) {
                price.value = scaled_impact - price.value;
                price.isPositive = false;
            } else {
                price.value = price.value - scaled_impact;
            };
        } else {
            price.value = price.value + scaled_impact;
        }
    };

    event::emit(PriceChangeEvent {
        supra_oracle_price: (supra_oracle_price as u256),
        old_qiara_oracle_price_impact: old_price_state, 
        new_qiara_oracle_price_impact: *price,   
        time: timestamp::now_seconds(),
    });

    // You need to decide if return value is % or the new absolute impact
    return calculate_impact_percentage((supra_oracle_price as u256), price.value, price.isPositive)
}

    fun ensure_price(prices: &mut Prices, name: String, oracleID: u64): &mut Integer{
        if (!map::contains_key(&prices.map, &name)) {
            map::upsert(&mut prices.map, name, Integer {  oracleID: oracleID, value: 0, isPositive: true });
        };
        return map::borrow_mut(&mut prices.map, &name)
    }


    #[view]
    public fun convert_to_usd(name: String, size: u256): u256 acquires Prices{
        let price = viewPrice(name);

        //1000000000000000000*1000000000000000000/1000000000000000000

        return(price*size)/1000000000000000000
    }

    #[view]
    public fun convert_to_token(name: String, usd: u256): u256 acquires Prices{
        let price = viewPrice(name);
        return (usd*1000000000000000000)/price
    }

    #[view]
    public fun viewAllPrices(name: String): Map<String, Integer> acquires Prices{

        borrow_global_mut<Prices>(@dev).map

    }

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices{

        let prices = borrow_global_mut<Prices>(@dev);

        if (!map::contains_key(&prices.map, &name)) {
            abort(ERROR_TOKEN_PRICE_COULDNT_BE_FOUND)
        };

        let qiara_impact = map::borrow(&prices.map, &name);
        let (supra_oracle_price, _, _, _) = supra_oracle_storage::get_price((qiara_impact.oracleID as u32));

        if(qiara_impact.isPositive){
            return (supra_oracle_price as u256)+qiara_impact.value
        } else {
            return (supra_oracle_price as u256)-qiara_impact.value
        }

    }

    #[view]
    public fun viewPriceMulti(name: vector<String>): Map<String, u256> acquires Prices{

        let map = map::new<String, u256>();
        let len = vector::length(&name);
        while(len>0){
            map::upsert(&mut map, *vector::borrow(&name, len-1), viewPrice(*vector::borrow(&name, len-1)));
            len=len-1;
        };
        return map

    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices{

        let prices = borrow_global_mut<Prices>(@dev);

        if (!map::contains_key(&prices.map, &name)) {
            return false
        };

        return true

    }

    #[view]
    public fun calculate_impact_percentage(supra_oracle_price: u256, impact: u256,  isPositive: bool): u256 {
        // Avoid division by zero
        if (supra_oracle_price == 0) { return 0 };

        if (isPositive) {
            // Returns the price multiplier (e.g., 1.05 * 1e18)
            return ((supra_oracle_price + impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        } else {
            // Prevent underflow if impact is greater than price
            if (impact >= supra_oracle_price) {
                return 0 // Price cannot be less than zero
            };
            return ((supra_oracle_price - impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        }
    }

}
