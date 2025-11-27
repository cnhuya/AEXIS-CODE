module dev::QiaraTokensBridgeStorageV4{
    use std::signer;
    use std::bcs;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::from_bcs;
    use supra_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use std::table::{Self, Table};
    use std::timestamp;

    use dev::QiaraTokensMetadataV4::{Self as TokensMetadata};


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

    struct BridgeLock<phantom T> has key {
        balance: coin::Coin<T>,
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

    public fun init_lock<Token>(admin: &signer) {
        if (!exists<BridgeLock<Token>>(@dev)) {
            move_to(admin, BridgeLock<Token> { balance: coin::zero<Token>() });
        };
    }

    public fun change_TokenSupply<Token, Chain>(amount: u64, isMint: bool, perm: Permission) acquires CrosschainBook {
        let book = borrow_global_mut<CrosschainBook>(@dev);
        if (!table::contains(&book.book, type_info::type_name<Token>())) {
            table::add(&mut book.book, type_info::type_name<Token>(), map::new<String, u256>());
        };

        let token_book = table::borrow_mut(&mut book.book, type_info::type_name<Token>());
        if (!map::contains_key(token_book, &type_info::type_name<Chain>())) {
            map::add(token_book, type_info::type_name<Chain>(), (amount as u256));
        } else {
            let current = map::borrow_mut(token_book, &type_info::type_name<Chain>());
            if(isMint){
                map::upsert(token_book, type_info::type_name<Chain>(), *current + (amount as u256));
            } else {
                if(*current < (amount as u256)){
                    return
                } else {
                map::upsert(token_book, type_info::type_name<Chain>(), *current - (amount as u256));
                }
            };
        }   
    }
    public fun change_UserTokenSupply<Token, Chain>(address: vector<u8>, amount: u64, isMint: bool, perm: Permission) acquires UserCrosschainBook {
        let book = borrow_global_mut<UserCrosschainBook>(@dev);
        if (!table::contains(&book.book, address)) {
            table::add(&mut book.book, address, table::new<String, Map<String, u256>>());
        };

        let user_book = table::borrow_mut(&mut book.book, address);
        if(!table::contains(user_book, type_info::type_name<Token>())) {
            table::add(user_book, type_info::type_name<Token>(), map::new<String, u256>());
        };

        let user = table::borrow_mut(user_book, type_info::type_name<Token>());

        if (!map::contains_key(user, &type_info::type_name<Chain>())) {
            map::add( user, type_info::type_name<Chain>(), (amount as u256));
        } else {
            let current = map::borrow_mut( user, &type_info::type_name<Chain>());
            if(isMint){
                map::upsert(user, type_info::type_name<Chain>(), *current + (amount as u256));
            } else {
                if(*current < (amount as u256)){
                    return;
                } else {
                map::upsert(user, type_info::type_name<Chain>(), *current - (amount as u256));
                }
            };
        }   
    }

    public fun p_mint<Token, Chain>(address: vector<u8>, amount: u64, perm: Permission) acquires UserCrosschainBook, CrosschainBook {
        change_TokenSupply<Token, Chain>(amount, true, copy perm);
        change_UserTokenSupply<Token, Chain>(address, amount, true,   perm);
    }
    public fun p_burn<Token, Chain>(address: vector<u8>, amount: u64, perm: Permission) acquires UserCrosschainBook, CrosschainBook{
        change_TokenSupply<Token, Chain>(amount, false, copy perm);
        change_UserTokenSupply<Token, Chain>(address, amount, false,  perm);
    }

    // Function to pre-"burn" tokens when bridging out, but the transaction isnt yet validated so the tokens arent really burned yet.
    // Later implement function to claim locked tokens if the bridge tx fails
    public fun lock<Token, Chain>(user: &signer, coins: Coin<Token>, perm: Permission) acquires BridgeLock{
        let lock = borrow_global_mut<BridgeLock<Token>>(@dev);
        coin::merge(&mut lock.balance, coins);
    }

    public fun unlock<Token, Chain>(user: &signer, amount: u64, perm: Permission): Coin<Token> acquires BridgeLock{
        let lock = borrow_global_mut<BridgeLock<Token>>(@dev);
        return coin::extract<Token>(&mut lock.balance, amount)
    }

// === VIEW FUNCTIONS === //
    
    #[view]
    public fun return_global_balances<Token>(): Map<String, u256> acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        if (!table::contains(&book.book, type_info::type_name<Token>())) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };

        return *table::borrow(&book.book, type_info::type_name<Token>())

    }


    #[view]
    public fun return_global_balance<Token, Chain>(): u256 acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        if (!table::contains(&book.book, type_info::type_name<Token>())) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };

        let table = table::borrow(&book.book, type_info::type_name<Token>());

        if(!map::contains_key(table, &type_info::type_name<Chain>())) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

        return *map::borrow(table, &type_info::type_name<Chain>())

    }
    
    #[view]
    public fun return_balances<Token>(address: vector<u8>): Map<String, u256> acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);
        if (!table::contains(&book.book, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };

        let user_book = table::borrow(&book.book, address);
        if(!table::contains(user_book, type_info::type_name<Token>())) {
            abort ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED
        };

        return *table::borrow(user_book, type_info::type_name<Token>())

    }


    #[view]
    public fun return_balance<Token, Chain>(address: vector<u8>): u256 acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);
        if (!table::contains(&book.book, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };

        let user_book = table::borrow(&book.book, address);
        if(!table::contains(user_book, type_info::type_name<Token>())) {
            abort ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED 
        };
        let table = table::borrow(user_book, type_info::type_name<Chain>());
        if(!map::contains_key(table, &type_info::type_name<Chain>())) {
            abort ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED
        };

        return *map::borrow(table, &type_info::type_name<Chain>())

    }
}