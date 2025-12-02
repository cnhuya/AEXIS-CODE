module dev::QiaraTokensRatesV27 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table::{Self as table, Table};
    use std::timestamp;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraMathV9::{Self as Math};

    use dev::QiaraChainTypesV19::{Self as ChainTypes};
    use dev::QiaraTokenTypesV19::{Self as TokensType};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
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

    // Tracks Lending Rates across chains for each token & its supported chains
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)... -> Rate
    struct RateList has key {
        rates: Table<String, Map<String, Rate>>
    }

    struct Rate has key, store, copy, drop {
        reward_index: u128,   // cumulative reward per unit deposited (scaled fixed-point)
        interest_index: u128,   // cumulative reward per unit deposited (scaled fixed-point)
        lend_rate: u64,       // per-second or per-block reward APR
        last_update: u64,     // last timestamp or block height
    }

// === INIT === //
    fun init_module(address: &signer){
        if (!exists<RateList>(signer::address_of(address))) {
            move_to(address, RateList {rates: table::new<String,Map<String, Rate>>()});
        };
    }


// === HELPER FUNCTIONS === //
    public entry fun change_rate(addr: &signer) acquires RateList {
        change_rates(utf8(b"QBTC"), utf8(b"Sui"), 8022, give_permission(&give_access(addr)));
        change_rates(utf8(b"QETH"), utf8(b"Sui"), 17147, give_permission(&give_access(addr)));
        change_rates(utf8(b"QETH"), utf8(b"Base"), 9874, give_permission(&give_access(addr)));
        change_rates(utf8(b"QSOL"), utf8(b"Solana"), 22578, give_permission(&give_access(addr)));
        change_rates(utf8(b"QSUI"), utf8(b"Sui"), 12011, give_permission(&give_access(addr)));
        change_rates(utf8(b"QDEEP"), utf8(b"Sui"), 13547, give_permission(&give_access(addr)));
        change_rates(utf8(b"QINJ"), utf8(b"Injective"), 16454, give_permission(&give_access(addr)));
        change_rates(utf8(b"QVIRTUALS"), utf8(b"Base"), 29331, give_permission(&give_access(addr)));
        change_rates(utf8(b"QSUPRA"), utf8(b"Supra"), 12974, give_permission(&give_access(addr)));
        change_rates(utf8(b"QUSDT"), utf8(b"Sui"), 29331, give_permission(&give_access(addr)));
        change_rates(utf8(b"QUSDC"), utf8(b"Base"), 12974, give_permission(&give_access(addr)));
        change_rates(utf8(b"QUSDC"), utf8(b"Sui"), 29331, give_permission(&give_access(addr)));
    }


    public fun change_rates(token: String, chain: String, lend_rate: u64, cap: Permission) acquires RateList {
        let rate = find_rate(borrow_global_mut<RateList>(@dev), token, chain);
        rate.lend_rate = (rate.lend_rate + lend_rate) / 2;
    }

    public fun accrue_global(token: String, chain: String, lend_rate: u256,exp_scale: u256,utilization: u256,total_deposits: u256,total_borrows: u256,_cap: Permission) acquires RateList {
        let rate = find_rate(borrow_global_mut<RateList>(@dev), token, chain);

        let now = timestamp::now_seconds();
        if (now <= rate.last_update) return;
        let elapsed = now - rate.last_update;
        if (elapsed == 0) return;

        if (total_deposits > 0) {
            let (lend_rate_decimal, _, _) = Math::compute_rate(utilization, lend_rate, exp_scale, true, 5);
            let reward_per_unit = ((((lend_rate_decimal / 1000) * 1_000_000) * (elapsed as u256)) / 31_536_000) / total_deposits;
            assert!((rate.reward_index as u256) + reward_per_unit <= (340282366920938463463374607431768211455u128 as u256), 1001);
            rate.reward_index = (((rate.reward_index as u256) + reward_per_unit) as u128);

            let (borrow_rate_decimal, _, _) = Math::compute_rate(utilization, lend_rate, exp_scale, false, 5);
            if (total_borrows > 0) {
                let interest_per_unit = (((borrow_rate_decimal / 1000) * 1_000_000) * (elapsed as u256) / 31_536_000) / total_borrows;
                assert!((rate.interest_index as u256) + interest_per_unit <= (340282366920938463463374607431768211455u128 as u256), 1002);
                rate.interest_index = (((rate.interest_index as u256) + interest_per_unit) as u128);
            };
        };

        rate.last_update = now;
    }

    public fun find_rate(x: &mut RateList, token: String, chain: String): &mut Rate {
        ChainTypes::ensure_valid_chain_name(&chain);
        TokensType::ensure_valid_token(&token);
        if (!table::contains(&x.rates, token)) {
            table::add(&mut x.rates, token, map::new<String, Rate>());
        };
        
        // Get mutable reference to the inner map directly
        let rates = table::borrow_mut(&mut x.rates, token);
        
        if (!map::contains_key(rates, &chain)) {
            map::add(rates, chain, Rate { 
                reward_index: 0, 
                interest_index: 0, 
                lend_rate: 0, 
                last_update: timestamp::now_seconds() 
            });
        };
        
        // Now borrow from the rates map and return it
        map::borrow_mut(rates, &chain)
    }


// === GETS === //

    #[view]
    public fun get_vaults(token: String): Map<String, Rate> acquires RateList{
        let x = borrow_global_mut<RateList>(@dev);
        if (!table::contains(&x.rates,  token)) {
            table::add(&mut x.rates,  token, map::new<String, Rate>());
        };
        return *table::borrow_mut(&mut x.rates,  token)
    }

    #[view]
    public fun get_vault_rate(token: String, chain: String): Rate acquires RateList{
        return *find_rate(borrow_global_mut<RateList>(@dev), token, chain)
    }

    #[view]
    public fun get_vault_raw(token: String, chain: String): (u64,u128,u128,u64) acquires RateList{
        let rate = find_rate(borrow_global_mut<RateList>(@dev), token, chain);
        return (rate.lend_rate,rate.reward_index,rate.interest_index,rate.last_update)
    }

    public fun get_vault_lend_rate(rate: Rate): u64{
        return rate.lend_rate
    }
    public fun get_vault_reward_index(rate: Rate): u128{
        return rate.reward_index
    }
    public fun get_vault_interest_index(rate: Rate): u128{
        return rate.interest_index
    }
    public fun get_vault_last_updated(rate: Rate): u64{
        return rate.last_update
    }
}
