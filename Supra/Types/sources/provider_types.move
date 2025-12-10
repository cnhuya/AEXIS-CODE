module dev::QiaraProviderTypesV21 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};

// === ERRORS === //
    const ERROR_INVALID_PROVIDER: u64 = 1;
// === STRUCTS === //

// provider -> chain -> tokens
    struct Providers has key{
        table: Table<String, Map<String, vector<String>>>
    }

// === INIT === //
    fun init_module(admin: &signer)acquires Providers{
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Providers>(@dev)) {
            move_to(admin, Providers { table: table::new<String, Map<String, vector<String>>>() });
        };

        x_init(admin);
    }


    fun x_init(signer: &signer) acquires Providers{
        register_new_provider(signer, utf8(b"Juplend"), utf8(b"Solana"));
        register_new_provider(signer, utf8(b"Kamino"), utf8(b"Solana"));
        register_new_provider(signer, utf8(b"Neptune"), utf8(b"Injective"));
        register_new_provider(signer, utf8(b"Moonwell"), utf8(b"Base"));
        register_new_provider(signer, utf8(b"Morpho"), utf8(b"Base"));
        register_new_provider(signer, utf8(b"Suilend"), utf8(b"Sui"));
        register_new_provider(signer, utf8(b"Alphalend"), utf8(b"Sui"));
        register_new_provider(signer, utf8(b"Navi"), utf8(b"Sui"));
        register_new_provider(signer, utf8(b"Supralend"), utf8(b"Supra"));

        allow_tokens_for_provider(signer,  utf8(b"Juplend"), utf8(b"Solana"), vector[utf8(b"Solana")]);
        allow_tokens_for_provider(signer,  utf8(b"Kamino"), utf8(b"Solana"), vector[utf8(b"Solana")]);
        allow_tokens_for_provider(signer,  utf8(b"Neptune"), utf8(b"Injective"), vector[utf8(b"Injective")]);
        allow_tokens_for_provider(signer,  utf8(b"Moonwell"), utf8(b"Base"), vector[utf8(b"USDC"),utf8(b"Ethereum") ,utf8(b"Virtuals")]);
        allow_tokens_for_provider(signer,  utf8(b"Morpho"), utf8(b"Base"), vector[utf8(b"USDC"),utf8(b"Ethereum") ,utf8(b"Virtuals")]);
        allow_tokens_for_provider(signer,  utf8(b"Suilend"), utf8(b"Sui"), vector[utf8(b"USDC"),utf8(b"USDT"),utf8(b"Ethereum"),utf8(b"Bitcoin"),utf8(b"Sui"),utf8(b"Deepbook")]);
        allow_tokens_for_provider(signer,  utf8(b"Alphalend"), utf8(b"Sui"), vector[utf8(b"USDC"),utf8(b"USDT"),utf8(b"Ethereum"),utf8(b"Bitcoin"),utf8(b"Sui"),utf8(b"Deepbook")]);
        allow_tokens_for_provider(signer,  utf8(b"Navi"), utf8(b"Sui"), vector[utf8(b"USDC"),utf8(b"USDT"),utf8(b"Ethereum"),utf8(b"Bitcoin"),utf8(b"Sui"),utf8(b"Deepbook")]);
        allow_tokens_for_provider(signer,  utf8(b"Supralend"), utf8(b"Supra"), vector[utf8(b"Supra"),utf8(b"Qiara")]);
    } 

    public entry fun register_new_provider(signer: &signer, provider: String, chain: String) acquires Providers{
        let provider_table = borrow_global_mut<Providers>(@dev);
        
        if (!table::contains(&provider_table.table, provider)) {
            table::add(&mut provider_table.table, provider, map::new<String, vector<String>>());
        };

        let chains_map = table::borrow_mut(&mut provider_table.table, provider);

        if (!map::contains_key(chains_map, &chain)) {
            map::upsert(chains_map, chain, vector::empty<String>());
        };
    }

    public entry fun allow_tokens_for_provider(signer: &signer, provider: String, chain: String, new_tokens: vector<String>) acquires Providers{
        register_new_provider(signer, provider, chain);

        let provider_table = borrow_global_mut<Providers>(@dev);
        let chains_map = table::borrow_mut(&mut provider_table.table, provider);
        let tokens = map::borrow_mut(chains_map, &chain);
        
        let tokens_len = vector::length(&new_tokens);
        while(tokens_len>0){
            let token = vector::borrow(&new_tokens, tokens_len-1);
            if(!vector::contains(tokens, token)){
                vector::push_back(tokens, *token);
            };
            tokens_len=tokens_len-1;
        };
    }

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
