module dev::QiaraOracleV3 {
    use std::string::{Self as string, String, utf8};
    use std::bcs;
    use pyth::pyth;
    use pyth::price;
    use pyth::price::Price;
    use pyth::price_identifier;
    use pyth::i64;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraEventV1::{Self as Event};

    // ── Error codes ────────────────────────────────────────────────────────────
    const E_NOT_INITIALIZED:  u64 = 1;
    const E_ALREADY_INIT:     u64 = 2;
    const E_NEGATIVE_PRICE:   u64 = 3;
    const E_STALE_PRICE:      u64 = 4;
    const E_FEED_ID_EMPTY:    u64 = 5;

    // ── Max age for "fresh" price: 60 seconds ──────────────────────────────────
    const MAX_AGE_SECS: u64 = 60;

    struct PriceStore has key, store, drop, copy {
        price:        i64::I64,
        expo:         i64::I64,
        publish_time: u64,
    }

    struct Prices has key, store {
        prices: Map<String, PriceStore>,
    }

    // ── Init ───────────────────────────────────────────────────────────────────
    fun init_module(admin: &signer) {
        move_to(admin, Prices { prices: map::new<String, PriceStore>() });
    }

    // ── Update + cache ─────────────────────────────────────────────────────────
    public entry fun update_price(user: &signer,price_update_data: vector<vector<u8>>,feed_id_bytes: vector<u8>) acquires Prices {
        assert!(exists<Prices>(@dev), E_NOT_INITIALIZED);
        assert!(std::vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);

        let feed_id_str = utf8(feed_id_bytes); 
        let cached_price = get_price(feed_id_str);

        let fee = pyth::get_update_fee(&price_update_data);
        let coins = coin::withdraw<AptosCoin>(user, fee);
        pyth::update_price_feeds(price_update_data, coins);

        let price_id = price_identifier::from_byte_vec(feed_id_bytes);
        let p: Price = pyth::get_price_no_older_than(price_id, MAX_AGE_SECS);

        let raw = price::get_price(&p);
        assert!(!i64::get_is_negative(&raw), E_NEGATIVE_PRICE);


        let prices = borrow_global_mut<Prices>(@dev);
        let new_store = PriceStore {
            price: raw,
            expo: price::get_expo(&p),
            publish_time: price::get_timestamp(&p),
        };

        let old_price =  i64::get_magnitude_if_positive(&cached_price.price);
        let new_price = i64::get_magnitude_if_positive(&new_store.price);
        // Emit Event
        let data = vector[
            Event::create_data_struct(utf8(b"oracle id"), utf8(b"string"), bcs::to_bytes(&feed_id_str)),
            Event::create_data_struct(utf8(b"old_price"), utf8(b"u64"), bcs::to_bytes(&old_price)),
            Event::create_data_struct(utf8(b"new_price"), utf8(b"u64"), bcs::to_bytes(&new_price)),
        ];
        Event::emit_oracle_event(utf8(b"Price Update"), data);

        if (map::contains_key(&prices.prices, &feed_id_str)) {
            *map::borrow_mut(&mut prices.prices, &feed_id_str) = new_store;
        } else {
            map::add(&mut prices.prices, feed_id_str, new_store);
        }
    }

    fun ensure_price(feed_id_str: String, price_store: PriceStore) acquires Prices {
        let prices = borrow_global_mut<Prices>(@dev);
        map::upsert(&mut prices.prices, feed_id_str, price_store);
    }

    // ── Read from cache ────────────────────────────────────────────────────────
    #[view]
    public fun get_price(feed_id_str: String): PriceStore acquires Prices {
        let prices = borrow_global_mut<Prices>(@dev);

        if (!map::contains_key(&prices.prices, &feed_id_str)) {
            return PriceStore { price: i64::new(0, false), expo: i64::new(0, false), publish_time: 0 }
        };

        *map::borrow_mut(&mut prices.prices, &feed_id_str)
    }

    // ── Direct read from Pyth (no cache) ───────────────────────────────────────
    #[view]
    public fun get_price_direct(feed_id_bytes: vector<u8>): (i64::I64, i64::I64, u64) {
        assert!(std::vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);

        let price_id = price_identifier::from_byte_vec(feed_id_bytes);
        let p: Price = pyth::get_price_no_older_than(price_id, MAX_AGE_SECS);
        (
            price::get_price(&p),
            price::get_expo(&p),
            price::get_timestamp(&p),
        )
    }
}