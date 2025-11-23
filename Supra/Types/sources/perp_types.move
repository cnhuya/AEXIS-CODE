module dev::PerpTypesV12 {
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};

    // === STRUCTS === //
    struct Bitcoin has store, key { }
    struct Ethereum has store, key { }
    struct Solana has store, key { }
    struct Sui has store, key { }
    struct Injective has store, key { }
    struct Deepbook has store, key { }
    struct Aerodrome has store, key { }
    struct Virtuals has store, key { }
    struct Supra has store, key { }
    struct USDC has store, key { }
    struct USDT has store, key { }

// === HELPER FUNCTIONS === //
    #[view]
    public fun return_all_perp_types(): vector<String> {
        vector[
            type_info::type_name<Bitcoin>(),
            type_info::type_name<Ethereum>(),
            type_info::type_name<Solana>(),
            type_info::type_name<Sui>(),
            type_info::type_name<Injective>(),
            type_info::type_name<Deepbook>(),
            type_info::type_name<Aerodrome>(),
            type_info::type_name<Virtuals>()
        ]
    }

    public fun convert_chainType_to_string<T>(): String {
        let type_name = type_info::type_name<T>();
        
        if (type_name == type_info::type_name<Bitcoin>()) {
            utf8(b"Bitcoin")
        } else if (type_name == type_info::type_name<Ethereum>()) {
            utf8(b"Ethereum")
        } else if (type_name == type_info::type_name<Solana>()) {
            utf8(b"Solana")
        } else if (type_name == type_info::type_name<Sui>()) {
            utf8(b"Sui")
        } else if (type_name == type_info::type_name<Injective>()) {
            utf8(b"Injective")
        } else if (type_name == type_info::type_name<Deepbook>()) {
            utf8(b"Deepbook")
        } else if (type_name == type_info::type_name<Aerodrome>()) {
            utf8(b"Aerodrome")
        } else if (type_name == type_info::type_name<Virtuals>()) {
            utf8(b"Virtuals")
        } else {
            utf8(b"Unknown")
        }
    }

    // Additional helper functions
    #[view]
    public fun is_valid_perp_type<T>(): bool {
        let type_name = type_info::type_name<T>();
        type_name == type_info::type_name<Bitcoin>() ||
        type_name == type_info::type_name<Ethereum>() ||
        type_name == type_info::type_name<Solana>() ||
        type_name == type_info::type_name<Sui>() ||
        type_name == type_info::type_name<Injective>() ||
        type_name == type_info::type_name<Deepbook>() ||
        type_name == type_info::type_name<Aerodrome>() ||
        type_name == type_info::type_name<Virtuals>()
    }
}