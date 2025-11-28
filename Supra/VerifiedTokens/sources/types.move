module dev::QiaraTokensTypesV5{
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::string::{Self as string, String, utf8};
    use supra_framework::managed_coin::{Self};
    use supra_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use std::type_info::{Self, TypeInfo};

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


    #[view]
    public fun return_all_coin_types(): vector<String> {
        vector[
            type_info::type_name<Bitcoin>(),
            type_info::type_name<Ethereum>(),
            type_info::type_name<Solana>(),
            type_info::type_name<Sui>(),
            type_info::type_name<Injective>(),
            type_info::type_name<Deepbook>(),
            type_info::type_name<Aerodrome>(),
            type_info::type_name<Virtuals>(),
            type_info::type_name<Supra>()
        ]
    }

    #[view]
    public fun convert_coinType_to_string<T>(): String {
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
        } else if (type_name == type_info::type_name<Supra>()) {
            utf8(b"Supra")
        } else {
            utf8(b"Unknown")
        }
    }

    #[view]
    public fun is_valid_coin_type<Token>(): bool {
        let type_name = type_info::type_name<Token>();
        type_name == type_info::type_name<Bitcoin>() ||
        type_name == type_info::type_name<Ethereum>() ||
        type_name == type_info::type_name<Solana>() ||
        type_name == type_info::type_name<Sui>() ||
        type_name == type_info::type_name<Injective>() ||
        type_name == type_info::type_name<Deepbook>() ||
        type_name == type_info::type_name<Aerodrome>() ||
        type_name == type_info::type_name<Virtuals>() ||
        type_name == type_info::type_name<Supra>()
    }
 }

