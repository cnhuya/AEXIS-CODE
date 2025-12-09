module dev::QiaraProviderTypesV20 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
// === ERRORS === //
    const ERROR_INVALID_PROVIDER: u64 = 1;
// === STRUCTS === //
    struct Market has store, key { }
    struct Perpetuals has store, key { }

// In the future implement storage which allows checks what chains does provider support, and which coins are allowed.
// [Table(chain -> Map(provider, vector<tokens>))]
// i.e Base -> Moonwell -> <ETH,AERO,VIRTUALS,USDC...>

// === FUNCTIONS === //
    #[view]
    public fun return_all_providers(): vector<String> {
        vector[
            utf8(b"Morpho"), // BASE
            utf8(b"Moonwell"), // BASE
            utf8(b"Navi"), // SUI
            utf8(b"Suilend"), // SUI
            utf8(b"Alphalend"), // SUI
            utf8(b"Neptune"), // INJECTIVE
            utf8(b"Supralend"), // SUPRA
            utf8(b"SupraStaking"), // SUPRA - native staking
            utf8(b"Juplend"), // SOLANA
            utf8(b"Kamino"), // SOLANA
            utf8(b"Save"), // SOLANA
        ]
    }

    public fun ensure_valid_provider(provider: &String) {
        assert!(vector::contains(&return_all_providers(), provider), ERROR_INVALID_PROVIDER);
    }

}
