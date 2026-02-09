module dev::QiaraTokensOmnichainV12{
    use std::signer;
    use std::bcs;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};

    use dev::QiaraTokensRouterV1::{Self as TokensRouter};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED: u64 = 2;
    const ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED: u64 = 3;
    const ERROR_ADDRESS_NOT_INITIALIZED: u64 = 4;
    const ERROR_TOKEN_NOT_INITIALIZED: u64 = 5;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 6;
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
    // Tracks permissioneless "liqudity" (i.e without having to use Supra directed Wallets or anything like that...) across chains for each address
    // i.e 0x...123 (user) -> Ethereum (token) -> Base/Sui/Solana (chains)... -> supply
    struct P_UserCrosschainBook has key{
        book: Table<vector<u8>, Table<String, Map<String, u256>>>
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<CrosschainBook>(@dev)) {
            move_to(admin, CrosschainBook { book: table::new<String,Map<String, u256>>() });
        };
        if (!exists<UserCrosschainBook>(@dev)) {
            move_to(admin, UserCrosschainBook { book: table::new<vector<u8>,Table<String, Map<String, u256>>>() });
        };

    }

// === HELPERS === //

    fun tttta(r: u64){
        abort(r)
    }

    public fun change_TokenSupply(token:String, chain:String, amount: u64, isMint: bool, perm: Permission) acquires CrosschainBook {
        let book = borrow_global_mut<CrosschainBook>(@dev);
        let token_type = token;
        let chain_type = chain;
        
        if (!table::contains(&book.book, token_type)) {
            table::add(&mut book.book, token_type, map::new<String, u256>());
        };
        
        let token_book = table::borrow_mut(&mut book.book, token_type);
        
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
    public fun change_UserTokenSupply(token:String, chain:String, address: vector<u8>, amount: u64, isMint: bool, perm: Permission) acquires UserCrosschainBook {
        let book = borrow_global_mut<UserCrosschainBook>(@dev);
        let token_type = token;
        let chain_type = chain;

        if (!table::contains(&book.book, address)) {
            table::add(&mut book.book, address, table::new<String, Map<String, u256>>());
        };

        let user_book = table::borrow_mut(&mut book.book, address);
        if(!table::contains(user_book, token_type)) {
            table::add(user_book, token_type, map::new<String, u256>());
        };

        let user = table::borrow_mut(user_book, token_type);

        if (!map::contains_key(user, &chain_type)) {
            map::add( user, chain_type, (amount as u256));
        } else {
            let current = map::borrow_mut( user, &chain_type);
            if(isMint){
                map::upsert(user, chain_type, *current + (amount as u256));
            } else {
                if(*current < (amount as u256)){
                    return;
                } else {
                map::upsert(user, chain_type, *current - (amount as u256));
                }
            };
        }   
    }

    public fun p_mint(token:String, chain:String,address: vector<u8>, amount: u64, perm: Permission) acquires UserCrosschainBook, CrosschainBook {
        change_TokenSupply(token, chain,amount, true, copy perm);
        change_UserTokenSupply(token, chain,address, amount, true,   perm);
    }
    public fun p_burn(token:String, chain:String, address: vector<u8>, amount: u64, perm: Permission) acquires UserCrosschainBook, CrosschainBook{
        change_TokenSupply(token, chain,amount, false, copy perm);
        change_UserTokenSupply(token, chain,address, amount, false,  perm);
    }


// === VIEW FUNCTIONS === //
    
    #[view]
    public fun return_global_balances<Token>(token:String,): Map<String, u256> acquires CrosschainBook {
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
    public fun return_balances(token:String,address: vector<u8>): Map<String, u256> acquires UserCrosschainBook {
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
    public fun return_balance(token:String, chain:String, address: vector<u8>): u256 acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);
        if (!table::contains(&book.book, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };

        let user_book = table::borrow(&book.book, address);
        if(!table::contains(user_book, token)) {
            abort ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED 
        };
        let table = table::borrow(user_book, chain);
        if(!map::contains_key(table, &chain)) {
            abort ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED
        };

        return *map::borrow(table, &chain)

    }
}