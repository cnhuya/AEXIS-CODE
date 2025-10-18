module dev::QiaraChainTypesV11 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};

// === STRUCTS === //
    struct Supra has store, key { }
    struct Sui has store, key { }
    struct Base has store, key { }

// === HELPER FUNCTIONS === //
    public fun return_all_chain_types(): vector<String>{
        return vector<String>[type_info::type_name<Supra>(),type_info::type_name<Sui>(),type_info::type_name<Base>()]
    }

    public fun convert_chainType_to_string<T>(): String{
        let type = type_info::type_name<T>();
        if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisChainTypesV1::Sui") ){
            return utf8(b"Sui")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisChainTypesV1::Supra") ){
            return utf8(b"Supra")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::AexisChainTypesV1::Base") ){
            return utf8(b"Base")
        } else{
            return utf8(b"Unknown")
        }
    }

}
