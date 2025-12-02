module dev::QiaraTokenTypesV19 {
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
    public fun ensure_valid_token(token: &String): String {
        assert!(vector::contains(&return_all_tokens(), token), ERROR_INVALID_TOKEN);

        if(token == &utf8(b"Bitcoin")){
            return utf8(b"Qiara15 Bitcoin")
        } else if (token == &utf8(b"Ethereum")){
            return utf8(b"Qiara15 Ethereum")        
        } else if (token == &utf8(b"Solana")){
            return utf8(b"Qiara15 Solana")        
        } else if (token == &utf8(b"Sui")){
            return utf8(b"Qiara15 Sui") 
        } else if (token == &utf8(b"Virtuals")){
            return utf8(b"Qiara15 Virtuals")        
        } else if (token == &utf8(b"Deepbook")){
            return utf8(b"Qiara15 Deepbook")        
        } else if (token == &utf8(b"Supra")){
            return utf8(b"Qiara15 Supra")        
        } else if (token == &utf8(b"Injective")){
            return utf8(b"Qiara15 Injective")        
        } else if (token == &utf8(b"USDC")){
            return utf8(b"Qiara15 USDC")        
        } else if (token == &utf8(b"USDT")){
            return utf8(b"Qiara15 USDT")        
        } else {
            abort(ERROR_INVALID_TOKEN)   
        }
    }

    public fun convert_token_to_symbol(token: &String): String {
        assert!(vector::contains(&return_all_tokens(), token), ERROR_INVALID_TOKEN);

        if(token == &utf8(b"Qiara15 Bitcoin")){
            return utf8(b"QBTC")
        } else if (token == &utf8(b"Qiara15 Ethereum")){
            return utf8(b"QETH")        
        } else if (token == &utf8(b"Qiara15 Solana")){
            return utf8(b"QSOL")        
        } else if (token == &utf8(b"Qiara15 Sui")){
            return utf8(b"QSUI") 
        } else if (token == &utf8(b"Qiara15 Virtuals")){
            return utf8(b"QVIRTUALS")        
        } else if (token == &utf8(b"Qiara15 Deepbook")){
            return utf8(b"QDEEP")        
        } else if (token == &utf8(b"Qiara15 Supra")){
            return utf8(b"QSUPRA")        
        } else if (token == &utf8(b"Qiara15 Injective")){
            return utf8(b"QINJ")        
        } else if (token == &utf8(b"Qiara15 USDC")){
            return utf8(b"QUSDC")        
        } else if (token == &utf8(b"Qiara15 USDT")){
            return utf8(b"QUSDT")        
        } else {
            abort(ERROR_INVALID_TOKEN)   
        }
    }
}
