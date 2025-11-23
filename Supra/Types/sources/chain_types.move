module dev::QiaraChainTypesV13 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};

// === STRUCTS === //
    struct Supra has store, key { }
    struct Sui has store, key { }
    struct Base has store, key { }

// === HELPER FUNCTIONS === //
    #[view]
    public fun return_all_chain_types(): vector<String>{
        return vector<String>[type_info::type_name<Supra>(),type_info::type_name<Sui>(),type_info::type_name<Base>()]
    }

    public fun convert_chainType_to_string<T>(): String{
        let type = type_info::type_name<T>();
        if(type == utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::AexisChainTypesV13::Sui") ){
            return utf8(b"Sui")
        } else if(type == utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::AexisChainTypesV13::Supra") ){
            return utf8(b"Supra")
        } else if(type == utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::AexisChainTypesV13::Base") ){
            return utf8(b"Base")
        } else{
            return utf8(b"Unknown")
        }
    }

}
