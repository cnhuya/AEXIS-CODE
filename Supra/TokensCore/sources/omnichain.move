module dev::QiaraTokensOmnichainV35{
    use std::signer;
    use std::bcs;
    use std::timestamp;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};
    use supra_framework::event;

    use dev::QiaraChainTypesV19::{Self as ChainTypes};
    use dev::QiaraTokenTypesV19::{Self as TokensType};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED: u64 = 2;
    const ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED: u64 = 3;
    const ERROR_ADDRESS_NOT_INITIALIZED: u64 = 4;
    const ERROR_TOKEN_NOT_INITIALIZED: u64 = 5;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 6;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 7;
    
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

// === STRUCTS === //

    // Tracks allowed/supported chains for each Token.
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)
    struct TokensChains has key{
        book: Map<String, vector<String>>
    }
    // Tracks overall "liqudity" across chains for each token type (the string argument)
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)... -> supply
    struct CrosschainBook has key{
        book: Table<String, Map<String, u256>>
    }
    // Tracks "liqudity" across chains for each address
    // i.e 0x...123 (user) -> Ethereum (token) -> Base/Sui/Solana (chains)... -> supply
    struct UserCrosschainBook has key{
        book: Table<vector<u8>, Table<String, Map<String, u256>>>
    }

    // This is useless for now?
    // Tracks permissioneless "liqudity" (i.e without having to use Supra directed Wallets or anything like that...) across chains for each address
    // i.e 0x...123 (user) -> Ethereum (token) -> Base/Sui/Solana (chains)... -> supply
    // struct P_UserCrosschainBook has key{
    //    book: Table<vector<u8>, Table<String, Map<String, u256>>>
    // }


// === EVENTS === //
    #[event]
    struct MintEvent has copy, drop, store {
        address: vector<u8>,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct BurnEvent has copy, drop, store {
        address: vector<u8>,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<TokensChains>(@dev)) {
            move_to(admin, TokensChains { book: map::new<String, vector<String>>() });
        };
        if (!exists<CrosschainBook>(@dev)) {
            move_to(admin, CrosschainBook { book: table::new<String,Map<String, u256>>() });
        };
        if (!exists<UserCrosschainBook>(@dev)) {
            move_to(admin, UserCrosschainBook { book: table::new<vector<u8>,Table<String, Map<String, u256>>>() });
        };
    }

    fun tttta(id: u64){
        abort(id);
    }

// === HELPERS === //

    public fun change_TokenSupply(token:String, chain:String, amount: u64, isMint: bool, perm: Permission) acquires CrosschainBook, TokensChains {
       // ChainTypes::ensure_valid_chain_name(&chain);
       // TokensType::ensure_valid_token(&token);
      
        let book = borrow_global_mut<CrosschainBook>(@dev);
        let chains = borrow_global_mut<TokensChains>(@dev);
        let token_type = token;
        let chain_type = chain;
        
        if (!map::contains_key(&chains.book, &token_type)) {
            map::upsert(&mut chains.book, token_type, vector::empty<String>());
        };
        let chains = map::borrow_mut(&mut chains.book, &token_type);
        vector::push_back(chains, chain);

        if (!table::contains(&book.book, token_type)) {
            table::add(&mut book.book, token_type, map::new<String, u256>());
        };
        
        let token_book = table::borrow_mut(&mut book.book, token_type);
        ensure_token_supports_chain(token, chain);
 
        // Force the logic without else
        if (map::contains_key(token_book, &chain_type)) {
            let current_supply = map::borrow_mut(token_book, &chain_type);
            if (isMint) {
                *current_supply = *current_supply + (amount as u256);
            } else {
                assert!(*current_supply >= (amount as u256), 99999);
                *current_supply = *current_supply - (amount as u256);
            }
        } else {
            map::upsert(token_book, chain_type, (amount as u256));
        }   
    }
public fun change_UserTokenSupply(
    token: String, 
    chain: String, 
    address: vector<u8>, 
    amount: u64, 
    isMint: bool, 
    perm: Permission
) acquires UserCrosschainBook, TokensChains {
    
    let book = borrow_global_mut<UserCrosschainBook>(@dev);
    let chains = borrow_global_mut<TokensChains>(@dev);
    let token_type = token;
    let chain_type = chain;

    if (!map::contains_key(&chains.book, &token_type)) {
        map::upsert(&mut chains.book, token_type, vector::empty<String>());
    };
    let c = map::borrow_mut(&mut chains.book, &token_type);
    
    if (!vector::contains(c, &chain_type)) {
        vector::push_back(c, chain_type);
    };

    if (!table::contains(&book.book, address)) {
      //  tttta(100);
        table::add(&mut book.book, address, table::new<String, Map<String, u256>>());
    };

    let user_book = table::borrow_mut(&mut book.book, address);
    
    if(!table::contains(user_book, token_type)) {
        table::add(user_book, token_type, map::new<String, u256>());
    };
    
if(isMint){
            event::emit(MintEvent {
            address: address,
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
} else {
            event::emit(BurnEvent {
            address: address,
            token: token,
            chain: chain,
            amount: amount,
            time: timestamp::now_seconds() 
        });
};
    
    let user = table::borrow_mut(user_book, token_type);
   // tttta(1);
    // 5. Handle the amount change
    if (!map::contains_key(user, &chain_type)) {
        // First time for this chain
        if (isMint) {
            map::add(user, chain_type, (amount as u256));
        } else {
            // Can't withdraw from zero balance
            // For withdrawals, we should have checked balance first
            // But initialize with 0 anyway
            map::add(user, chain_type, (0 as u256));
        };
   // tttta(5);
    } else {
        let current = map::borrow_mut(user, &chain_type);
        if (isMint) {
            *current = *current + (amount as u256);
        } else {
            // Check for underflow
            if (*current < (amount as u256)) {
                // Handle underflow - either abort or set to 0
                // *current = (0 as u256); // Option 1: Set to 0
                abort ERROR_INSUFFICIENT_BALANCE // Option 2: Abort (recommended)
            } else {
                *current = *current - (amount as u256);
            };
        };
    //tttta(500);
    }

}


// === VIEW FUNCTIONS === //
    
    #[view]
    public fun return_supported_chains(token:String): vector<String> acquires TokensChains {
        let book = borrow_global<TokensChains>(@dev);
        if (!map::contains_key(&book.book, &token)) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };
        return *map::borrow(&book.book, &token)
    }


    public fun ensure_token_supports_chain(token: String, chain:String) acquires TokensChains{
        assert!(vector::contains(&return_supported_chains(token), &chain), ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN)
    }

    #[view]
    public fun return_global_balances(token:String): Map<String, u256> acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        if (!table::contains(&book.book, token)) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };

        return *table::borrow(&book.book, token)

    }

    #[view]
    public fun return_global_balance(token:String,chain: String): u256 acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        if (!table::contains(&book.book, token)) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };

        let table = table::borrow(&book.book, token);

        if(!map::contains_key(table, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

        return *map::borrow(table, &chain)

    }
    
    #[view]
    public fun return_address_balances(token:String,address: vector<u8>): Map<String, u256> acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);
        if (!table::contains(&book.book, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };

        let user_book = table::borrow(&book.book, address);
        if(!table::contains(user_book, token)) {
            abort ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED
        };

        return *table::borrow(user_book, token)

    }

    #[view]
    public fun return_adress_balance(token:String, chain:String, address: vector<u8>): u256 acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);
        if (!table::contains(&book.book, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };

        let user_book = table::borrow(&book.book, address);
        if(!table::contains(user_book, token)) {
            abort ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED 
        };
        let table = table::borrow(user_book, token);
        if(!map::contains_key(table, &chain)) {
            abort ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED
        };

        return *map::borrow(table, &chain)

    }
}