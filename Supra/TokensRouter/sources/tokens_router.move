module dev::QiaraTokensRouterV3 {
    use std::type_info::{Self, TypeInfo};
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use supra_framework::object::{Self, Object};
    use supra_framework::fungible_asset::{Self, Metadata};

    use dev::QiaraTokenTypesV4::{Self as TokensType};

// === HELPER FUNCTIONS === //
    #[view]
    public fun get_metadata(symbol:String): Object<Metadata> {
        let asset_address = object::create_object_address(&@dev, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(symbol)));
        object::address_to_object<Metadata>(asset_address)
    }

}
