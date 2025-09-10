module dev::AexisVaultProviderTypesV2 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};

    //Sui
    struct AlphaLend has store, key { }
    struct SuiLend has store, key { }
    //Base
    struct Moonwell has store, key { }


    // JUST A HELP FUNCTION
    public fun convert_vaultProvider_to_string<T>(): String{
        let type = type_info::type_name<T>();
        if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProvidersV1::AlphaLend") ){
            return utf8(b"AlphaLend")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProvidersV1::SuiLend") ){
            return utf8(b"SuiLend")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisVaultProvidersV1::Moonwell") ){
            return utf8(b"Moonwell")
        } else{
            return utf8(b"Unknown")
        }
    }

}
