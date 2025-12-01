module dev::QiaraTokenTypesV18 {
    use std::string::{Self as string, String, utf8};
    use std::vector;


// === ERRORS === //
    const ERROR_INVALID_TOKEN: u64 = 1;

// === FUNCTIONS === //
    #[view]
    public fun return_all_tokens(): vector<String> {
        vector[
            utf8(b"Bitcoin"),
            utf8(b"Ethereum"),
            utf8(b"Solana"),
            utf8(b"Sui"),
            utf8(b"Deepbook"),
            utf8(b"Virtuals"),
            utf8(b"Supra"),
            utf8(b"Injective"),
            utf8(b"USDC"),
            utf8(b"USDT"), 
        ]
    }

    public fun ensure_valid_token(token: &String) {
        assert!(vector::contains(&return_all_tokens(), token), ERROR_INVALID_TOKEN)
    }
}
