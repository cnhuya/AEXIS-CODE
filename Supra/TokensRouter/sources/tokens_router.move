module dev::QiaraTokensRouterV1 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use std::bcs;
    use supra_framework::object::{Self, Object};
    use supra_framework::fungible_asset::{Self, Metadata};

// === STRUCTS === //
    struct Supra has store, key { }
    struct Sui has store, key { }
    struct Base has store, key { }
    struct Injective has store, key { }
    struct Solana has store, key { }


// === HELPER FUNCTIONS === //
    #[view]
    public fun get_metadata<Token>(): Object<Metadata> {
        let asset_address = object::create_object_address(&@dev, bcs::to_bytes(&type_info::type_name<Token>()));
        object::address_to_object<Metadata>(asset_address)
    }

}
