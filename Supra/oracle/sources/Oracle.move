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
