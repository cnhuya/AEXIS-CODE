module dev::QiaraFeatureTypesV11 {
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
        if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraFeatureTypesV1::Market") ){
            return utf8(b"Market")
        } else if(type == utf8(b"0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd::QiaraFeatureTypesV1::Perpetuals") ){
            return utf8(b"Perpetuals")
        } else{
            return utf8(b"Unknown")
        }
    }
}
