module dev::QiaraVaultTypesV4 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table;
    use std::timestamp;

    use dev::QiaraMath::{Self as Math};

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
        rates: table::Table<String, Rate>, 
    }

    struct Rate has key, store, copy, drop {
        reward_index: u128,   // cumulative reward per unit deposited (scaled fixed-point)
        interest_index: u128,   // cumulative reward per unit deposited (scaled fixed-point)
        lend_rate: u64,       // per-second or per-block reward APR
        last_update: u64,     // last timestamp or block height
    }

    fun init_module(address: &signer){
        if (!exists<RateList>(signer::address_of(address))) {
            move_to(address, RateList {rates: table::new<String, Rate>()});
        };
    }

    public fun change_rates<X>(lend_rate: u64, borrow_rate: u64, cap: Permission) acquires RateList {
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

    public fun accrue_global<X>(lend_rate: u256, exp_scale: u256, utilization: u256, total_deposits: u256, total_borrows: u256, cap: Permission) acquires RateList {

        let rates = borrow_global_mut<RateList>(@dev);
        let rate = table::borrow_mut(&mut rates.rates, type_info::type_name<X>());

        let seconds_in_year: u256 = 31_536_000;
        let elapsed = timestamp::now_seconds() - rate.last_update;
        if (elapsed == 0) return;

        // Update reward index (distributes reward over all deposits)
        if (total_deposits > 0) {
            let lend_rate_decimal: u256 = Math::compute_rate(lend_rate,exp_scale,utilization,18) / 10000; 
            let reward_per_unit = (lend_rate_decimal * (elapsed as u256) / seconds_in_year) / total_deposits;
            rate.reward_index = (((rate.reward_index as u256) + reward_per_unit) as u128);

            let borrow_rate_decimal: u256 = Math::compute_rate(lend_rate,exp_scale,utilization,18) / 10000; 
            let interest_per_unit = (borrow_rate_decimal * (elapsed as u256) / seconds_in_year) / total_borrows;
            rate.interest_index = (((rate.interest_index as u256) + interest_per_unit) as u128);
        };

        rate.last_update = timestamp::now_seconds();
    }


// === GETS === //
    public fun get_vault_rate(res: String): Rate acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, res);
        return *rate
    }

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
        return rate.reward_index
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
