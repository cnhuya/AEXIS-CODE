module dev::QiaraFeatureTypesV13 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};

// === STRUCTS === //
    struct Market has store, key { }
    struct Perpetuals has store, key { }
// === HELPER FUNCTIONS === //
    public fun return_all_feature_types(): vector<String>{
        return vector<String>[type_info::type_name<Market>(),type_info::type_name<Perpetuals>()]
    }

    public fun convert_featureType_to_string<T>(): String{
        let type = type_info::type_name<T>();
        if(type == utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraFeatureTypesV13::Market") ){
            return utf8(b"Market")
        } else if(type == utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraFeatureTypesV13::Perpetuals") ){
            return utf8(b"Perpetuals")
        } else{
            return utf8(b"Unknown")
        }
    }
}
