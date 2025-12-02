module dev::QiaraTokenTypesV19 {
    use std::string::{Self as string, String, utf8};
    use std::vector;


const TOKEN_PREFIX: vector<u8> = b"Qiara15 ";
const SYMBOL_PREFIX: vector<u8> = b"Q";

// === ERRORS === //
    const ERROR_INVALID_TOKEN: u64 = 1;
    const ERROR_INVALID_CONVERT_TOKEN: u64 = 2;
    const ERROR_INVALID_CONVERT_SYMBOL: u64 = 3;

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
// Define constants at the module level

public fun ensure_valid_token(token: &String): String {
    assert!(vector::contains(&return_all_tokens(), token), ERROR_INVALID_TOKEN);
    
    let full_token_name = string::utf8(TOKEN_PREFIX);
    
    if(token == &utf8(b"Bitcoin")){
        string::append_utf8(&mut full_token_name, b"Bitcoin");
    } else if (token == &utf8(b"Ethereum")){
        string::append_utf8(&mut full_token_name, b"Ethereum");        
    } else if (token == &utf8(b"Solana")){
        string::append_utf8(&mut full_token_name, b"Solana");        
    } else if (token == &utf8(b"Sui")){
        string::append_utf8(&mut full_token_name, b"Sui"); 
    } else if (token == &utf8(b"Virtuals")){
        string::append_utf8(&mut full_token_name, b"Virtuals");        
    } else if (token == &utf8(b"Deepbook")){
        string::append_utf8(&mut full_token_name, b"Deepbook");        
    } else if (token == &utf8(b"Supra")){
        string::append_utf8(&mut full_token_name, b"Supra");        
    } else if (token == &utf8(b"Injective")){
        string::append_utf8(&mut full_token_name, b"Injective");        
    } else if (token == &utf8(b"USDC")){
        string::append_utf8(&mut full_token_name, b"USDC");        
    } else if (token == &utf8(b"USDT")){
        string::append_utf8(&mut full_token_name, b"USDT");        
    } else {
        abort(ERROR_INVALID_TOKEN);   
    };
    
    full_token_name
}

public fun convert_token_to_symbol(token: &String): String {
    assert!(vector::contains(&return_all_tokens(), token), ERROR_INVALID_TOKEN);
    
    let symbol = string::utf8(SYMBOL_PREFIX);
    
    if(token == &utf8(b"Qiara15 Bitcoin")){
        string::append_utf8(&mut symbol, b"BTC");
    } else if (token == &utf8(b"Qiara15 Ethereum")){
        string::append_utf8(&mut symbol, b"ETH");        
    } else if (token == &utf8(b"Qiara15 Solana")){
        string::append_utf8(&mut symbol, b"SOL");        
    } else if (token == &utf8(b"Qiara15 Sui")){
        string::append_utf8(&mut symbol, b"SUI"); 
    } else if (token == &utf8(b"Qiara15 Virtuals")){
        string::append_utf8(&mut symbol, b"VIRTUALS");        
    } else if (token == &utf8(b"Qiara15 Deepbook")){
        string::append_utf8(&mut symbol, b"DEEP");        
    } else if (token == &utf8(b"Qiara15 Supra")){
        string::append_utf8(&mut symbol, b"SUPRA");        
    } else if (token == &utf8(b"Qiara15 Injective")){
        string::append_utf8(&mut symbol, b"INJ");        
    } else if (token == &utf8(b"Qiara15 USDC")){
        string::append_utf8(&mut symbol, b"USDC");        
    } else if (token == &utf8(b"Qiara15 USDT")){
        string::append_utf8(&mut symbol, b"USDT");        
    } else {
        abort(ERROR_INVALID_CONVERT_TOKEN);   
    };
    
    symbol
}

public fun convert_symbol_to_token(symbol: &String): String {
    let full_token_name = string::utf8(TOKEN_PREFIX);
    
    if(symbol == &utf8(b"QBTC")){
        string::append_utf8(&mut full_token_name, b"Bitcoin");
    } else if (symbol == &utf8(b"QETH")){
        string::append_utf8(&mut full_token_name, b"Ethereum");        
    } else if (symbol == &utf8(b"QSOL")){
        string::append_utf8(&mut full_token_name, b"Solana");        
    } else if (symbol == &utf8(b"QSUI")){
        string::append_utf8(&mut full_token_name, b"Sui"); 
    } else if (symbol == &utf8(b"QVIRTUALS")){
        string::append_utf8(&mut full_token_name, b"Virtuals");        
    } else if (symbol == &utf8(b"QDEEP")){
        string::append_utf8(&mut full_token_name, b"Deepbook");        
    } else if (symbol == &utf8(b"QSUPRA")){
        string::append_utf8(&mut full_token_name, b"Supra");        
    } else if (symbol == &utf8(b"QINJ")){
        string::append_utf8(&mut full_token_name, b"Injective");        
    } else if (symbol == &utf8(b"QUSDC")){
        string::append_utf8(&mut full_token_name, b"USDC");        
    } else if (symbol == &utf8(b"QUSDT")){
        string::append_utf8(&mut full_token_name, b"USDT");        
    } else {
        abort(ERROR_INVALID_CONVERT_SYMBOL);   
    };
    
    full_token_name
}

// Helper function to get full token name with prefix
public fun get_full_token_name(base_token: &String): String {
    let full_name = string::utf8(TOKEN_PREFIX);
    string::append(&mut full_name, *base_token);
    full_name
}

// Helper function to get symbol with prefix
public fun get_symbol(base_symbol: &String): String {
    let symbol = string::utf8(SYMBOL_PREFIX);
    string::append(&mut symbol, *base_symbol);
    symbol
}
}
