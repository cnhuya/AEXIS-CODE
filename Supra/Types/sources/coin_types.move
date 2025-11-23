module dev::QiaraCoinTypesV14{
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use supra_framework::managed_coin::{Self};
    use supra_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use std::type_info::{Self, TypeInfo};
    use supra_framework::supra_coin::{Self, SupraCoin};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::option::{Option};

    use dev::QiaraMathV9::{Self as Math};
// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_INVALID_COIN_TYPE: u64 = 2;
    const ERROR_UNKNOWN_ERROR: u64 = 3;
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(): Access {
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
// === STRUCTS === //

    struct SuiBitcoin has drop, store, key {}
    struct SuiSui has drop, store, key {}
    struct SuiEthereum has drop, store, key {}
    struct SuiUSDC has drop, store, key {}
    struct SuiUSDT has drop, store, key {}

    struct BaseEthereum has drop, store, key {}
    struct BaseUSDC has drop, store, key {}

    struct Capabilities<CoinType> has key {
        burn_cap: BurnCapability<CoinType>,
        mint_cap: MintCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
    }

    // View Struct
    struct CoinData has store, key, drop {
        resource: String,
        name: String,
        symbol: String,
        decimals: u8,
        supply: Option<u128>, 
    }

// i.e Bitcoin -> SuiBitcoin, BaseBitcoin... any bridged bitcoin... (for METADATA properties such as tokenomics etc, which determines the tier of the asset)
    struct RouterBook has key{
        book: Map<String, vector<String>>
    }

// === INIT === //
    fun init_module(admin: &signer) acquires RouterBook {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<RouterBook>(@dev)) {
            move_to(admin, RouterBook { book: map::new<String, vector<String>>() });
        };

        init_coin<SuiBitcoin>(admin, utf8(b"Sui Bitcoin"),   utf8(b"SUIBTC"),utf8(b"Bitcoin"), 8);
        init_coin<SuiEthereum>(admin, utf8(b"Sui Ethereum"), utf8(b"SUIETH"),utf8(b"Ethereum"), 8);
        init_coin<SuiSui>(admin,     utf8(b"Sui SUI"),       utf8(b"SUISUI"),utf8(b"Sui"), 8);
        init_coin<SuiUSDC>(admin,    utf8(b"Sui USDC"),      utf8(b"SUIUSDC"),utf8(b"USDC"), 8);
        init_coin<SuiUSDT>(admin,    utf8(b"Sui USDT"),      utf8(b"SUIUSDT"),utf8(b"USDT"), 8);

        init_coin<BaseEthereum>(admin,    utf8(b"Base Ethereum"),      utf8(b"BASEBTC"),utf8(b"Ethereum"), 8);
        init_coin<BaseUSDC>(admin,    utf8(b"Base USDC"),      utf8(b"BASEUSDC"),utf8(b"USDC"), 8);
    }
// === INIT COIN === //
    public entry fun init_coin<T: store>(admin: &signer, name: String, symbol: String, router: String, decimals: u8,) acquires RouterBook {
        assert!(signer::address_of(admin) == @dev, 1);

        let router_book = borrow_global_mut<RouterBook>(@dev);

        if (!map::contains_key(&router_book.book, &router)) {
            map::add(&mut router_book.book, router, vector::empty<String>());
        };

        let book = map::borrow_mut(&mut router_book.book, &router);
        let type_name = type_info::type_name<T>();

        if (!vector::contains(book, &type_name)) {
            vector::push_back(book, type_name);
        };

        if (!exists<Capabilities<T>>(signer::address_of(admin))) {
            let (burn_cap, freeze_cap, mint_cap) = coin::initialize<T>(
                admin,
                name,
                symbol,
                decimals,
                true
            );

            register<T>(admin);

            let caps = Capabilities<T> { burn_cap, mint_cap, freeze_cap };
            move_to(admin, caps);
        };
    }
// === HELPERS === //
    fun mint<CoinType: store>(amount: u64, perm: Permission): Coin<CoinType> acquires Capabilities {
        coin::mint(amount, &borrow_global<Capabilities<CoinType>>(@dev).mint_cap)
    }

    fun burn<CoinType: store>(coins: Coin<CoinType>, perm: Permission) acquires Capabilities{
        coin::burn(coins, &borrow_global<Capabilities<CoinType>>(@dev).burn_cap)
    }

    // User coin registration
    public entry fun register<CoinType>(user: &signer) {
        managed_coin::register<CoinType>(user);
    }

// === FUNCTIONS === //
    // Public native deposit
    public entry fun deposit<CoinType: store>(banker: &signer, amount: u64) acquires Capabilities{
        let coins = coin::withdraw<CoinType>(banker, amount);
        burn<CoinType>(coins, give_permission(&give_access()));
    }

    // Convenience transfer (standard user transfer)
    public entry fun transfer<CoinType>(sender: &signer, recipient: address, amount: u64) {
        coin::transfer<CoinType>(sender, recipient, amount);
    }

    // Only validator can use, to mint new "bridged" tokens
    public fun withdraw_to<CoinType: store>(banker: &signer, cap: Permission, recipient: address, amount: u64) acquires Capabilities {
        let who = signer::address_of(banker);
        //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);

        let coins = mint<CoinType>(amount, give_permission(&give_access()));
        coin::deposit<CoinType>(recipient, coins);
    }

// DEPRECATED?
/*
    public fun extract_to<T>(banker: &signer, cap: Permission, recipient: address, amount: u64): Coin<T> acquires Capabilities {
        register<T>(banker);
        let who = signer::address_of(banker);
        //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);

        let vault = borrow_global_mut<Vault<T>>(@dev);
        coin::extract(&mut vault.balance, amount)
    }
*/
// === UNSAFE HELPER FUNCTIONS === //
    // For testing

    public entry fun unsafe_withdraw_to<CoinType : store>(banker: &signer,recipient: address, amount: u64) acquires Capabilities {
        let who = signer::address_of(banker);
        assert!(who == @0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0, ERROR_NOT_VALIDATOR);

        let coins = mint<CoinType>(amount, give_permission(&give_access()));
        coin::deposit<CoinType>(recipient, coins);
    }

// DEPREACTED?    
/* 
    public fun unsafe_extract_to<T>(banker: &signer, recipient: address, amount: u64): Coin<T> acquires Capabilities {
        let who = signer::address_of(banker);
        assert!(who == @0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0, ERROR_NOT_VALIDATOR);

        let vault = borrow_global_mut<Vault<T>>(@dev);
        coin::extract(&mut vault.balance, amount)
    }
*/
    #[view]
    public fun return_all_coin_types(): vector<String>{
        return vector<String>[type_info::type_name<SuiBitcoin>(),type_info::type_name<SuiEthereum>(),type_info::type_name<SuiSui>(),
        type_info::type_name<SuiUSDC>(),type_info::type_name<SuiUSDT>(),type_info::type_name<BaseEthereum>(),type_info::type_name<BaseUSDC>()]
    }
// === VIEW FUNCTIONS === //
    #[view]
    public fun balance_of<T>(addr: address): u64 {
        coin::balance<T>(addr)
    }

    #[view]
    public fun get_router<T>(): String acquires RouterBook{

        let keys = map::keys(&borrow_global<RouterBook>(@dev).book);
        let len = vector::length(&keys);

        while(len>0){
            let key = vector::borrow(&keys, len-1);
            if(*key == type_info::type_name<T>()){
                return *key
            };
            len=len-1;
        };
         abort ERROR_UNKNOWN_ERROR
    }
 // === GET COIN DATA === //
        #[view]
        public fun get_coin_data<Token>(): CoinData {
            let type = type_info::type_name<Token>();
            CoinData { resource: type, name: coin::name<Token>(), symbol: coin::symbol<Token>(), decimals: coin::decimals<Token>(), supply: coin::supply<Token>() }
        }

        public fun get_coin_type<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.resource
        }

        public fun get_coin_name<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.name
        }

        public fun get_coin_symbol<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.symbol
        }

        public fun get_coin_decimals<Token>(): u8 {
            let coin_data = get_coin_data<Token>();
            coin_data.decimals
        }

        public fun get_coin_denom<Token>(): u256 {
            let coin_data = get_coin_data<Token>();
            Math::pow10_u256((coin_data.decimals as u8))
        }

        public fun get_coin_supply<Token>(): Option<u128> {
            let coin_data = get_coin_data<Token>();
            coin_data.supply
        }



}
