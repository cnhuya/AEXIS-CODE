module dev::QiaraVaultTypesV9 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::signer;
    use std::table;
    use std::timestamp;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use dev::QiaraMathV9::{Self as Math};

    use dev::QiaraCoinTypesV9::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
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

// === INIT === //
    fun init_module(address: &signer){
        if (!exists<RateList>(signer::address_of(address))) {
            move_to(address, RateList {rates: table::new<String, Rate>()});
        };
    }
// === HELPER FUNCTIONS === //
//SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC
    public entry fun change_rate(addr: &signer) acquires RateList {
        change_rates<SuiBitcoin>(32022,give_permission(&give_access(addr)));
        change_rates<SuiEthereum>(100147,give_permission(&give_access(addr)));
        change_rates<SuiSui>(250578,give_permission(&give_access(addr)));
        change_rates<SuiUSDC>(50987,give_permission(&give_access(addr)));
        change_rates<SuiUSDT>(71151,give_permission(&give_access(addr)));
        change_rates<BaseEthereum>(99174,give_permission(&give_access(addr)));
        change_rates<BaseUSDC>(66855,give_permission(&give_access(addr)));
        change_rates<SupraCoin>(712987,give_permission(&give_access(addr)));
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

fun ttta(number: u64){
    abort(number)
}

public fun accrue_global<X>(
    lend_rate: u256,
    exp_scale: u256,
    utilization: u256,
    total_deposits: u256,
    total_borrows: u256,
    cap: Permission
) acquires RateList {
    let rates = borrow_global_mut<RateList>(@dev);
    let rate = table::borrow_mut(&mut rates.rates, type_info::type_name<X>());

    let seconds_in_year: u256 = 31_536_000;
    let elapsed = timestamp::now_seconds() - rate.last_update;
    if (elapsed == 0) return;

    if (total_deposits > 0) {
        let (lend_rate_decimal, _, _) = Math::compute_rate(utilization, lend_rate, exp_scale, true, 6);
        let lend_rate_decimal = lend_rate_decimal / 10000;
        let reward_per_unit = (lend_rate_decimal * (elapsed as u256) / seconds_in_year) / total_deposits;
        rate.reward_index = (((rate.reward_index as u256) + reward_per_unit) as u128);

        let (borrow_rate_decimal, _, _) = Math::compute_rate(utilization, lend_rate, exp_scale, false, 6);
        let borrow_rate_decimal = borrow_rate_decimal / 10000;

        // Safeguard against division by zero
        if (total_borrows > 0) {
            let interest_per_unit = (borrow_rate_decimal * (elapsed as u256) / seconds_in_year) / total_borrows;
            rate.interest_index = (((rate.interest_index as u256) + interest_per_unit) as u128);
        };
    };

    rate.last_update = timestamp::now_seconds();
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

// === HELPER FUNCTIONS === //
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
