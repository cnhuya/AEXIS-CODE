module dev::QiaraVaultTypesV2 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table;

    const ERROR_NOT_ADMIN: u64 = 1;

    struct Access has store, key, drop {}
    struct Permission has key, drop {}


    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(s: &signer, access: &Access): Permission {
        Permission {}
    }

    // Global - No vault provider
    struct None has store, key { }

    //Sui
    struct AlphaLend has store, key { }
    struct SuiLend has store, key { }
    //Base
    struct Moonwell has store, key { }


    struct RateList has key {
        rates: table::Table<String, Rates>, 
    }

    struct Rate has key {
        reward_index: u128,   // cumulative reward per unit deposited (scaled fixed-point)
        interest_index: u128, // cumulative interest per unit borrowed
        last_update: u64,     // last timestamp or block height
        lend_rate: u64,       // per-second or per-block reward APR
        borrow_rate: u64,     // per-second or per-block interest APR
    }

    fun init_module(address: &signer){
        if (!exists<RateList>(signer::address_of(address))) {
            move_to(address, RateList {rates: table::new<String, Rates>()});
        };
    }

    public fun change_rates<X>(lend_rate: u64, borrow_rate: u64, cap: Permission) acquires RateList {
        let x = borrow_global_mut<RateList>(@dev);
        let key = type_info::type_name<X>();

        if (!table::contains(&x.rates, key)) {
            table::add(&mut x.rates, key, Rates { reward_index:0, interest_index:0 lend_rate, borrow_rate, last_update: timestamp::now_seconds() });
        } else {
            let rate = table::borrow_mut(&mut x.rates, key);

            // Blend with 50% weight
            rate.lend_rate = (rate.lend_rate + lend_rate) / 2;
            rate.borrow_rate = (rate.borrow_rate + borrow_rate) / 2;

            update_rate_state(rate);
        }
    }

    public fun accrue_global<X>() acquires RateList {

        let rates = borrow_global_mut<RateList>(@dev);
        let rate = table::borrow_mut(&rates.rates, type_info::type_name<X>());

        let now = timestamp::now_seconds();
        let SECONDS_PER_YEAR: u128 = 31_536_000;
        let elapsed = now - rate.last_update;

        if (elapsed == 0) return;

        // Scale factor for fixed-point math (1e18 recommended)
        let SCALE: u128 = 1000000000000000000;

        // Update reward index (distributes reward over all deposits)
        if (rate.total_deposits > 0) {
            let lend_rate_decimal: u128 = (rate.lend_rate as u128) * SCALE / 10000; // fixed-point 1e18
            let reward_per_unit = ((lend_rate_decimal * (elapsed as u128) * SCALE) / SECONDS_PER_YEAR) / (rate.total_deposits as u128);
            rate.reward_index = rate.reward_index + reward_per_unit;
        }

        // Update interest index (accrues cost over all borrows)
        if (rate.total_borrows > 0) {
            let borrow_rate_decimal: u128 = (rate.borrow_rate as u128) * SCALE / 10000; // fixed-point 1e18
            let interest_per_unit = ((borrow_rate_decimal * (elapsed as u128) * SCALE)  / SECONDS_PER_YEAR) / (rate.total_borrows as u128);
            rate.interest_index = rate.interest_index + interest_per_unit;
        }

        rate.last_update = now;
    }



// === CHANGES === //
    public fun get_vault_mutable_rate<X>(cap: Permission): &mut Rate acquires RateList{
        let x = borrow_global_mut<RateList>(@dev);
        let rate = table::borrow_mut(&x.rates, type_info::type_name<X>());
        return rate
    }

    public fun change_vault_borrow_rate(rate: &mut Rate, borrow_rate: u64){
        return rate.borrow_rate = borrow_rate;
    }
    public fun change_vault_lend_rate(rate: &mut Rate, lend_rate: u64){
        return rate.lend_rate = lend_rate;
    }
    public fun change_vault_reward_index(rate: &mut Rate, reward_index: u64){
        return rate.reward_index = reward_index;
    }
    public fun change_vault_interest_index(rate: &mut Rate, interest_index: u64){
        return rate.interest_index = interest_index;
    }
    public fun change_vault_last_updated(rate: &mut Rate, last: u64){
        return rate.last = last-update;
    }

// === GETS === //
    public fun get_vault_rate<X>(): Rate acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, type_info::type_name<X>());
        return rate
    }

    public fun get_vault_raw<X>(): (u64,u64,u64,u64,u64) acquires RateList{
        let x = borrow_global_mut<RateList>(@dev);
        let rate = table::borrow_mut(&x.rates, type_info::type_name<X>());
        return (rate.lend_rate, rate.borrow_rate, rate.reward_index, rate.interest_index, rate.last_update);
    }

    public fun get_vault_lend_rate(rate: Rate): u64{
        return rate.lend_rate
    }
    public fun get_vault_borrow_rate(rate: Rate): u64{
        return rate.borrow_rate
    }
    public fun get_vault_reward_index(rate: Rate): u64{
        return rate.reward_index
    }
    public fun get_vault_interest_index(rate: Rate): u64{
        return rate.interest_index
    }
    public fun get_vault_last_updated(rate: Rate): u64{
        return rate.last_update
    }

// === HELP FUNCTIONS === //
    public fun return_all_vault_provider_types(): vector<String>{
        return vector<String>[type_info::type_name<None>(), type_info::type_name<AlphaLend>(),type_info::type_name<SuiLend>(),type_info::type_name<Moonwell>()]
    }

    public fun convert_vaultProvider_to_string<T>(): String{
        let type = type_info::type_name<T>();
        if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProviderTypesV2::AlphaLend") ){
            return utf8(b"AlphaLend")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProviderTypesV2::SuiLend") ){
            return utf8(b"SuiLend")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProviderTypesV2::Moonwell") ){
            return utf8(b"Moonwell")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProviderTypesV2::None") ){
            return utf8(b"None")
        } else{
            return utf8(b"Unknown")
        }
    }

}
