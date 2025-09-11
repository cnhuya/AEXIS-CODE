module dev::AexisVaultAggregratoryV4 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::vector;
    use supra_framework::supra_coin::{Self, SupraCoin};

    use dev::AexisCoinTypesV2::{SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use dev::AexisVaultProviderTypesV2::{None, AlphaLend, SuiLend, Moonwell};
    use dev::QiaraCapabilitiesV19::{Self as capabilities, Access as CapabilitiesAccess};

    const ERROR_INVALID_COIN_TYPE: u64 = 1;

    // Only generic on provider (vault validator)
    struct RateList<T> has key {
        rates: vector<RateEntry>, 
    }

    // Wrapper to store heterogeneous entries
    struct RateEntry has copy, drop, store {
        type_info: type_info::TypeInfo,
        lend_rate: u64,
        borrow_rate: u64,
    }

    // create list of ratetables (vector)

    fun init_module(admin: &signer) {
             let alpha_rates = RateList<AlphaLend> {
                rates: vector[
                    RateEntry { type_info: type_info::type_of<SuiBitcoin>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiEthereum>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiSui>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiUSDC>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiUSDT>(), lend_rate: 500, borrow_rate: 700 }
                ]
            };
            move_to(admin, alpha_rates);

            let sui_rates = RateList<SuiLend> {
                rates: vector[
                    RateEntry { type_info: type_info::type_of<SuiBitcoin>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiEthereum>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiSui>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiUSDC>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<SuiUSDT>(), lend_rate: 500, borrow_rate: 700 }
                ]
            };
            move_to(admin, sui_rates);

            let moonwell_rates = RateList<Moonwell> {
                rates: vector[
                    RateEntry { type_info: type_info::type_of<BaseEthereum>(), lend_rate: 500, borrow_rate: 700 },
                    RateEntry { type_info: type_info::type_of<BaseUSDC>(), lend_rate: 500, borrow_rate: 700 }
                ]
            };
            move_to(admin, moonwell_rates);

            let none_rates = RateList<None> {
                rates: vector[

                    RateEntry { type_info: type_info::type_of<SuiBitcoin>(), lend_rate: 0, borrow_rate: 0 },
                    RateEntry { type_info: type_info::type_of<SuiEthereum>(), lend_rate: 0, borrow_rate: 0 },
                    RateEntry { type_info: type_info::type_of<SuiSui>(), lend_rate: 0, borrow_rate: 0 },
                    RateEntry { type_info: type_info::type_of<SuiUSDC>(), lend_rate: 0, borrow_rate: 0 },
                    RateEntry { type_info: type_info::type_of<SuiUSDT>(), lend_rate: 0, borrow_rate: 0 },
        
                    RateEntry { type_info: type_info::type_of<BaseEthereum>(), lend_rate: 0, borrow_rate: 0 },
                    RateEntry { type_info: type_info::type_of<BaseUSDC>(), lend_rate: 0, borrow_rate: 0 },

                    RateEntry { type_info: type_info::type_of<SupraCoin>(), lend_rate: 0, borrow_rate: 0 },
                ]
            };
            move_to(admin, none_rates);
    }

    // T is provider type
    // E is a coin type
    //implement function to change the rate for <T, E>

    public entry fun change_rates<T: store,E>(account: &signer, lend_rate: u64, borrow_rate: u64) acquires RateList{
        let x = borrow_global_mut<RateList<T>>(@dev);
        let len = vector::length(&x.rates);
        while(len>0){
            let ref = vector::borrow_mut(&mut x.rates, len-1);
            if(ref.type_info == type_info::type_of<E>()){
                ref.lend_rate = lend_rate;
                ref.borrow_rate = borrow_rate;
                return
            };
            len=len-1;
        };
        abort ERROR_INVALID_COIN_TYPE
    }


    // JUST A HELP FUNCTION
    #[view]
    public fun get_vault_provider<E: store, T: store>(): RateEntry acquires RateList{
        let x = borrow_global<RateList<T>>(@dev);
        let len = vector::length(&x.rates);
        while(len>0){
            let ref = vector::borrow(&x.rates, len-1);
            if(ref.type_info == type_info::type_of<E>()){
                return *ref
            };
            len=len-1;
        };
        abort ERROR_INVALID_COIN_TYPE
    }


    // JUST A HELP FUNCTION
    #[view]
    public fun get_lend_rate<E: store, T: store>(): u64 acquires RateList{
        let x = get_vault_provider<E,T>();
        return x.lend_rate
    }

    #[view]
    public fun get_borrow_rate<E: store, T: store>(): u64 acquires RateList{
        let x = get_vault_provider<E,T>();
        return x.borrow_rate
    }

}
