module dev::QiaraFeatureTypesV15 {
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
        if(type == type_info::type_name<Market>() ){
            return utf8(b"Market")
        } else if(type == type_info::type_name<Perpetuals>()){
            return utf8(b"Perpetuals")
        } else{
            return utf8(b"Unknown")
        }
    }
}
