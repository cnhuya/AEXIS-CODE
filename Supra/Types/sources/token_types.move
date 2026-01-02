module dev::QiaraTokenTypesV4 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};

    use dev::QiaraChainTypesV4::{Self as ChainTypes};

const TOKEN_PREFIX: vector<u8> = b"Qiara40 ";
const SYMBOL_PREFIX: vector<u8> = b"Q";

// === ERRORS === //
    const ERROR_INVALID_TOKEN: u64 = 1;
    const ERROR_INVALID_CONVERT_TOKEN: u64 = 2;
    const ERROR_INVALID_CONVERT_SYMBOL: u64 = 3;
    const ERROR_TOKEN_NOT_SUPPORTED_FOR_THIS_CHAIN: u64 = 4;
// === STRUCTS === //

    // Token -> chains
    // or Chain -> Tokens
    struct Tokens has key{
        map: Map<String, vector<String>>,
        nick_names: Map<String, String>,
    }

// === INIT === //
    fun init_module(admin: &signer) acquires Tokens{
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Tokens>(@dev)) {
            move_to(admin, Tokens { map: map::new<String, vector<String>>(), nick_names: map::new<String, String>() });
        };
        x_init(admin);
    }


    fun x_init(signer: &signer) acquires Tokens{
        register_token_with_chains(signer, utf8(b"Qiara40 Qiara"), utf8(b"Qiara"), vector[utf8(b"Sui"),utf8(b"Base"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 USDC"), utf8(b"USDC"), vector[utf8(b"Sui"),utf8(b"Base"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 USDT"), utf8(b"USDT"), vector[utf8(b"Sui"),utf8(b"Base"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Ethereum"), utf8(b"Ethereum"), vector[utf8(b"Sui"),utf8(b"Base"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Bitcoin"), utf8(b"Bitcoin"), vector[utf8(b"Sui"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Solana"), utf8(b"Solana"), vector[utf8(b"Solana"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Supra"), utf8(b"Supra"), vector[utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Injective"), utf8(b"Injective"), vector[utf8(b"Injective"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Sui"), utf8(b"Sui"), vector[utf8(b"Sui"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Deepbook"), utf8(b"Deepbook"), vector[utf8(b"Sui"),utf8(b"Supra")]);
        register_token_with_chains(signer, utf8(b"Qiara40 Virtuals"), utf8(b"Virtuals"), vector[utf8(b"Base"),utf8(b"Supra")]);
    } 

// === FUNCTIONS === //

    public entry fun register_token_with_chains(signer: &signer, token: String, nick_name: String, chains: vector<String>) acquires Tokens {
        let tokens = borrow_global_mut<Tokens>(@dev);

        let len_chains = vector::length(&chains);
        while(len_chains > 0){
            let chain = vector::borrow(&chains, len_chains-1);
            ChainTypes::ensure_valid_chain_name(*chain);
            len_chains=len_chains-1;
        };

        if (!map::contains_key(&tokens.map, &token)) {
            map::upsert(&mut tokens.map, token, chains);
        };

        if (!map::contains_key(&tokens.nick_names, &token)) {
            map::upsert(&mut tokens.nick_names, token, nick_name);
        };
    }

    #[view]
    public fun return_all_tokens(): Map<String, vector<String>> acquires Tokens{
        borrow_global_mut<Tokens>(@dev).map
    }

    #[view]
    public fun return_full_tokens_list(): vector<String> acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);
        map::keys(&tokens.map)
    }

    #[view]
    public fun return_full_nick_names_list(): vector<String> acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);
        map::values(&tokens.nick_names)
    }

    #[view]
    public fun return_full_nick_names(): Map<String, String>acquires Tokens{
        borrow_global_mut<Tokens>(@dev).nick_names
    }

    public fun ensure_token_supported_for_chain(token: String, chain: String) acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);

        if (!map::contains_key(&tokens.map, &token)) {
            abort ERROR_INVALID_TOKEN
        };

        let chains = map::borrow(&tokens.map, &token);
        assert!(vector::contains(chains, &chain), ERROR_TOKEN_NOT_SUPPORTED_FOR_THIS_CHAIN);
    }

    // Define constants at the module level

    #[view]
    public fun convert_token_nickName_to_name(nick_name: String): String acquires Tokens{
        
        let tokens = borrow_global_mut<Tokens>(@dev);

        let nick_names = map::values(&tokens.nick_names);
        assert!(vector::contains(&nick_names, &nick_name), ERROR_INVALID_TOKEN);
       // if (!map::contains_key(&tokens.nick_names, &nick_name)) {
       //     abort ERROR_INVALID_TOKEN
       // };

        let len = vector::length(&nick_names);
        while(len>0){
            let name = vector::borrow(&nick_names, len-1);
            if(*name == nick_name){
                let symbol = string::utf8(TOKEN_PREFIX);
                string::append_utf8(&mut symbol, *string::bytes(vector::borrow(&nick_names, len-1)));

                return symbol
            };
        len=len-1;
        }; 
        abort ERROR_INVALID_TOKEN
    }
    #[view]
    public fun convert_token_name_to_nickName(token_name: String): String acquires Tokens{
        
        let tokens = borrow_global_mut<Tokens>(@dev);

        let names = map::keys(&tokens.nick_names);
        let nick_names = map::values(&tokens.nick_names);
        assert!(vector::contains(&names, &token_name), ERROR_INVALID_TOKEN);
        let len = vector::length(&names);
        while(len>0){
            let name = vector::borrow(&names, len-1);
            if(*name == token_name){
                return *vector::borrow(&nick_names, len-1);
            };
        len=len-1;
        };
        abort ERROR_INVALID_TOKEN
    }

    public fun ensure_valid_token_nick_name(token_name: String) acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);

        let names = map::values(&tokens.nick_names);
        assert!(vector::contains(&names, &token_name), ERROR_INVALID_TOKEN);
    }
}
