module dev::QiaraVaultRatesV14 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table;
    use std::timestamp;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use dev::QiaraMathV9::{Self as Math};

    use dev::QiaraCoinTypesV14::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
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

    struct RateList has key {
        rates: table::Table<String, Rate>, 
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
            move_to(address, RateList {rates: table::new<String, Rate>()});
        };
    }
// === HELPER FUNCTIONS === //
    public entry fun change_rate(addr: &signer) acquires RateList {
        change_rates<SuiBitcoin>(8022,give_permission(&give_access(addr)));
        change_rates<SuiEthereum>(17147,give_permission(&give_access(addr)));
        change_rates<SuiSui>(22578,give_permission(&give_access(addr)));
        change_rates<SuiUSDC>(12011,give_permission(&give_access(addr)));
        change_rates<SuiUSDT>(13547,give_permission(&give_access(addr)));
        change_rates<BaseEthereum>(16454,give_permission(&give_access(addr)));
        change_rates<BaseUSDC>(12974,give_permission(&give_access(addr)));
        change_rates<SupraCoin>(29331,give_permission(&give_access(addr)));
    }


    public fun change_rates<X>(lend_rate: u64, cap: Permission) acquires RateList {
        let x = borrow_global_mut<RateList>(@dev);
        let key = type_info::type_name<X>();

        if (!table::contains(&x.rates, key)) {
            table::add(&mut x.rates, key, Rate { reward_index:0, interest_index:0, lend_rate, last_update: timestamp::now_seconds() });
        } else {
            let rate = table::borrow_mut(&mut x.rates, key);

            // Blend with 50% weight
            rate.lend_rate = (rate.lend_rate + lend_rate) / 2;
        }
    }

    public fun accrue_global<X>(lend_rate: u256,exp_scale: u256,utilization: u256,total_deposits: u256,total_borrows: u256,_cap: Permission) acquires RateList {
        if (!exists<RateList>(@dev)) return;

        let rates = borrow_global_mut<RateList>(@dev);
        if (!table::contains(&rates.rates, type_info::type_name<X>())) return;
        let rate = table::borrow_mut(&mut rates.rates, type_info::type_name<X>());

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


// === GETS === //
    public fun get_vault_rate(res: String): Rate acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, res);
        return *rate
    }

    #[view]
    public fun get_vault_raw(res: String): (u64,u128,u128,u64) acquires RateList{
        let x = borrow_global_mut<RateList>(@dev);
        let rate = table::borrow_mut(&mut x.rates, res);
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
