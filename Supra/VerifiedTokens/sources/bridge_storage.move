module dev::QiaraTokensBridgeStorageV5{
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

    struct BridgeLock<Chain> has key {
        balance: Object<FungibleStore<Chain>>, // private
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

    public fun init_lock<Chain>(admin: &signer) {
        if (!exists<BridgeLock<Chain>(@dev)) {
            let asset_address = object::create_object_address(signer::address_of(admin), bcs::to_bytes(&type_info::type_name<Token>()));
            let metadata = object::address_to_object<Metadata>(asset_address);
            let store = primary_fungible_store::ensure_primary_store_exists<Metadata>(signer::address_of(admin), metadata);
            move_to(admin, BridgeLock { balance: store });
        };
    }

    public fun change_TokenSupply<Chain>(fa: FungibleAsset, isMint: bool, perm: Permission) acquires CrosschainBook {
        let book = borrow_global_mut<CrosschainBook>(@dev);
        let token_type = fungible_asset::name(fungible_asset::metadata_from_asset(&fa));
        let chain_type = type_info::type_name<Chain>();
        let amount = fungible_asset::amount(&fa);
        
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
    public fun change_UserTokenSupply<Chain>(address: vector<u8>, fa: FungibleAsset, isMint: bool, perm: Permission) acquires UserCrosschainBook {
        let book = borrow_global_mut<UserCrosschainBook>(@dev);
        let token_type = fungible_asset::name(fungible_asset::metadata_from_asset(&fa));
        let chain_type = type_info::type_name<Chain>();
        let amount = fungible_asset::amount(&fa);

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

    public fun p_mint<Chain>(address: vector<u8>, fa: FungibleAsset, perm: Permission) acquires UserCrosschainBook, CrosschainBook {
        change_TokenSupply<Chain>(fa, true, copy perm);
        change_UserTokenSupply<Chain>(address, fa, true,   perm);
    }
    public fun p_burn<Chain>(address: vector<u8>, fa: FungibleAsset, perm: Permission) acquires UserCrosschainBook, CrosschainBook{
        change_TokenSupply<Chain>(fa, false, copy perm);
        change_UserTokenSupply<Chain>(address, fa, false,  perm);
    }

    // Function to pre-"burn" tokens when bridging out, but the transaction isnt yet validated so the tokens arent really burned yet.
    // Later implement function to claim locked tokens if the bridge tx fails
    public fun lock<Chain>(user: &signer, fa: FungibleAsset, lock: &mut BridgeLock<Chain>, perm: Permission){
        fungible_asset::deposit(&mut lock.balance, fa);
    }

    public fun unlock<Chain>(user: &signer, amount: u64, lock: &mut BridgeLock<Chain>, perm: Permission): FungibleAsset{
        return fungible_asset::withdraw(&mut lock.balance, amount)
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