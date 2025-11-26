module dev::QiaraChainTypesV15 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};

// === STRUCTS === //
    struct Supra has store, key { }
    struct Sui has store, key { }
    struct Base has store, key { }
    struct Injective has store, key { }
    struct Solana has store, key { }


// === HELPER FUNCTIONS === //
    #[view]
    public fun return_all_chain_types(): vector<String>{
        return vector<String>[type_info::type_name<Supra>(),type_info::type_name<Sui>(),type_info::type_name<Base>()]
    }

    public fun convert_chainType_to_string<T>(): String{
        let type = type_info::type_name<T>();
        if(type == type_info::type_name<Supra>() ){
            return utf8(b"Sui")
        } else if(type == type_info::type_name<Sui>() ){
            return utf8(b"Supra")
        } else if(type == type_info::type_name<Base>() ){
            return utf8(b"Base")
        } else if(type == type_info::type_name<Injective>() ){
            return utf8(b"Injective")
        } else if(type == type_info::type_name<Solana>() ){
            return utf8(b"Solana")
        } else{
            return utf8(b"Unknown")
        }
    }

}
