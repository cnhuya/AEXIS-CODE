module dev::QiaraTokenTypesV1 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};

    use dev::QiaraChainTypesV1::{Self as ChainTypes};

    const TOKEN_PREFIX: vector<u8> = b"Qiara54 ";
    const SYMBOL_PREFIX: vector<u8> = b"Q";

// === ERRORS === //
    const ERROR_INVALID_TOKEN: u64 = 1;
    const ERROR_INVALID_CONVERT_TOKEN: u64 = 2;
    const ERROR_INVALID_CONVERT_SYMBOL: u64 = 3;
    const ERROR_TOKEN_NOT_SUPPORTED_FOR_THIS_CHAIN: u64 = 4;
    const ERROR_TKN_ADDRESSES_CHAINS_LENGTH_MISMATCH: u64 = 5;
    const ERROR_TOKEN_ALREADY_REGISTERED: u64 = 6;
    const ERROR_TOKEN_ADDR_ALREADY_REGISTERED: u64 = 7;
    const ERROR_CHAIN_ALREADY_REGISTERED_FOR_THIS_TKN: u64 = 8;
// === STRUCTS === //

    struct Tokens has key{
        // Token -> vector<Chains>
        map: Map<String, vector<String>>,
        // address -> token 
        addr: Map<String, String>, // this is purely Quality Of Life, to easily get the token from the address, without the needs to create "complicated/"centralized" functions
        // token -> nick name??
        nick_names: Map<String, String>,
    }

// === INIT === //
    fun init_module(admin: &signer) acquires Tokens{
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Tokens>(@dev)) {
            move_to(admin, Tokens { map: map::new<String, vector<String>>(), addr: map::new<String, String>(), nick_names: map::new<String, String>() });
        };
        x_init(admin);
    }


fun x_init(signer: &signer) acquires Tokens {
    // 3 chains -> 3 addresses
    register_token_with_chains(signer, utf8(b"Qiara54 Qiara"), utf8(b"Qiara"), vector[utf8(b"0x8C9621E38f74c59b0B784894f12C0CD5bE8a2f02")], vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 USDC"), utf8(b"USDC"), vector[], vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 USDT"), utf8(b"USDT"), vector[], vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 Ethereum"), utf8(b"Ethereum"), vector[], vector[utf8(b"Sui"), utf8(b"Base"), utf8(b"Supra")]);
    
    // 2 chains -> 2 addresses
    register_token_with_chains(signer, utf8(b"Qiara54 Bitcoin"), utf8(b"Bitcoin"),vector[], vector[utf8(b"Sui"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 Solana"), utf8(b"Solana"), vector[], vector[utf8(b"Solana"), utf8(b"Supra")]);
    
    // 1 chain -> 1 address
    register_token_with_chains(signer, utf8(b"Qiara54 Supra"), utf8(b"Supra"), vector[], vector[utf8(b"Supra")]);
    
    // 2 chains -> 2 addresses
    register_token_with_chains(signer, utf8(b"Qiara54 Injective"), utf8(b"Injective"), vector[], vector[utf8(b"Injective"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 Sui"), utf8(b"Sui"), vector[], vector[utf8(b"Sui"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 Deepbook"), utf8(b"Deepbook"), vector[], vector[utf8(b"Sui"), utf8(b"Supra")]);
    
    register_token_with_chains(signer, utf8(b"Qiara54 Virtuals"), utf8(b"Virtuals"), vector[], vector[utf8(b"Base"), utf8(b"Supra")]);
}

// === FUNCTIONS === //

    public entry fun register_token_with_chains(signer: &signer, token: String, nick_name: String, token_address: vector<String>, chains: vector<String>) acquires Tokens {
        let tokens = borrow_global_mut<Tokens>(@dev);

        let len_chains = vector::length(&chains);
        while(len_chains > 0){
            let chain = vector::borrow(&chains, len_chains-1);
            ChainTypes::ensure_valid_chain_name(*chain);
            len_chains=len_chains-1;
        };

        if (!map::contains_key(&tokens.map, &token)) {
            map::upsert(&mut tokens.map, token, chains);
        } else {
            abort ERROR_TOKEN_ALREADY_REGISTERED
        };

        let len_addr = vector::length(&token_address);
        while(len_addr > 0){
            let addr = vector::borrow(&token_address, len_addr-1);
            if (!map::contains_key(&tokens.addr, addr)) {
                map::upsert(&mut tokens.addr, *addr, nick_name);
            } else {
                abort ERROR_TOKEN_ADDR_ALREADY_REGISTERED
            };
            len_addr=len_addr-1;
        };

        if (!map::contains_key(&tokens.nick_names, &token)) {
            map::upsert(&mut tokens.nick_names, token, nick_name);
        }  else {
            abort ERROR_TOKEN_ALREADY_REGISTERED
        };
    }

    public entry fun add_token_chain(signer: &signer, token: String, nick_name: String, token_address: String, chain: String) acquires Tokens {
        let tokens = borrow_global_mut<Tokens>(@dev);


        if (!map::contains_key(&tokens.map, &token)) {
            let map = map::borrow_mut(&mut tokens.map, &token);
          //  assert!(vector::contains(map, &chain), ERROR_CHAIN_ALREADY_REGISTERED_FOR_THIS_TKN);
            vector::push_back(map, chain);
        };

        if (!map::contains_key(&tokens.addr, &token_address)) {
            map::upsert(&mut tokens.addr, token_address, nick_name);
        } else {
            abort ERROR_TOKEN_ADDR_ALREADY_REGISTERED
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
    public fun return_full_nick_names(): Map<String, String> acquires Tokens{
        borrow_global_mut<Tokens>(@dev).nick_names
    }

    public fun ensure_token_supported_for_chain(token: String, chain: String) acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);

        if (!map::contains_key(&tokens.map, &token)) {
            abort ERROR_INVALID_TOKEN
        };
    }

    #[view]
    public fun return_name_from_address(addr: String): String acquires Tokens{
        let tokens = borrow_global_mut<Tokens>(@dev);

        if (!map::contains_key(&tokens.addr, &addr)) {
            abort ERROR_INVALID_TOKEN
        };

        *map::borrow(&tokens.addr, &addr)
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
