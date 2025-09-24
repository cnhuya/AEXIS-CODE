module dev::QiaraVaultTypesV1 {
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

    struct Rates has copy, drop, store {
        lend_rate: u64,
        borrow_rate: u64,
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
            table::add(&mut x.rates, key, Rates { lend_rate, borrow_rate });
        } else {
            let rate = table::borrow_mut(&mut x.rates, key);
            rate.lend_rate = lend_rate;
            rate.borrow_rate = borrow_rate;
        }
    }

    // JUST A HELP FUNCTION
    #[view]
    public fun get_vault_lend_rate<X>(): u64 acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, type_info::type_name<X>());
        return rate.lend_rate
    }

    #[view]
    public fun get_vault_borrow_rate<X>(): u64 acquires RateList{
        let x = borrow_global<RateList>(@dev);
        let rate = table::borrow(&x.rates, type_info::type_name<X>());
        return rate.borrow_rate
    }


    public fun return_all_vault_provider_types(): vector<String>{
        return vector<String>[type_info::type_name<None>(), type_info::type_name<AlphaLend>(),type_info::type_name<SuiLend>(),type_info::type_name<Moonwell>()]
    }

    // JUST A HELP FUNCTION
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
