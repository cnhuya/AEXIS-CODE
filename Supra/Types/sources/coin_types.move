module dev::QiaraCoinTypesV11{
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use supra_framework::managed_coin::{Self};
    use supra_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use std::type_info::{Self, TypeInfo};
    use supra_framework::supra_coin::{Self, SupraCoin};
// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
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

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        init_coin<SuiBitcoin>(admin, utf8(b"Sui Bitcoin"),   utf8(b"SUIBTC"), 8);
        init_coin<SuiEthereum>(admin, utf8(b"Sui Ethereum"), utf8(b"SUIETH"), 8);
        init_coin<SuiSui>(admin,     utf8(b"Sui SUI"),       utf8(b"SUISUI"), 8);
        init_coin<SuiUSDC>(admin,    utf8(b"Sui USDC"),      utf8(b"SUIUSDC"), 8);
        init_coin<SuiUSDT>(admin,    utf8(b"Sui USDT"),      utf8(b"SUIUSDT"), 8);

        init_coin<BaseEthereum>(admin,    utf8(b"Base Ethereum"),      utf8(b"BASEBTC"), 8);
        init_coin<BaseUSDC>(admin,    utf8(b"Base USDC"),      utf8(b"BASEUSDC"), 8);
    }
// === INIT COIN === //
    public entry fun init_coin<T: store>(admin: &signer, name: String, symbol: String, decimals: u8) {
        assert!(signer::address_of(admin) == @dev, 1);

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

}
