module dev::QiaraCoinTypesV5{
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

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
// === STRUCTS === //
    struct SuiBitcoin has drop, store, key {}
    struct SuiEui has drop, store, key {}
    struct SuiUSthereum has drop, store, key {}
    struct SuiSDC has drop, store, key {}
    struct SuiUSDT has drop, store, key {}

    struct BaseEthereum has drop, store, key {}
    struct BaseUSDC has drop, store, key {}

    // Vault holds all initially minted coins for a given T
    struct Vault<phantom T> has key {
        balance: coin::Coin<T>,
    }
// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        init_with_vault<SuiBitcoin>(admin, utf8(b"Sui Bitcoin"),   utf8(b"SUIBTC"), 8);
        init_with_vault<SuiEthereum>(admin, utf8(b"Sui Ethereum"), utf8(b"SUIETH"), 18);
        init_with_vault<SuiSui>(admin,     utf8(b"Sui SUI"),       utf8(b"SUISUI"), 9);
        init_with_vault<SuiUSDC>(admin,    utf8(b"Sui USDC"),      utf8(b"SUIUSDC"), 6);
        init_with_vault<SuiUSDT>(admin,    utf8(b"Sui USDT"),      utf8(b"SUIUSDT"), 6);

        init_with_vault<BaseEthereum>(admin,    utf8(b"Base Ethereum"),      utf8(b"BASEBTC"), 18);
        init_with_vault<BaseUSDC>(admin,    utf8(b"Base USDC"),      utf8(b"BASEUSDC"), 6);

    }

    // Initialize a single coin T and create a vault with full u64::MAX
    public entry fun init_with_vault<T: store>(admin: &signer, name: String, symbol: String, decimals: u8 ) {
        assert!(signer::address_of(admin) == @dev, 1);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<T>(admin,name,symbol,decimals,true);

        // Register ADMIN to hold balances of T
        register<T>(admin);

        let max_amount: u64 = 18446744073709551615;
        //let coins = managed_coin::mint<T>(admin, signer::address_of(admin), max_amount);
        let coins_minted = coin::mint(max_amount, &mint_cap);
        // Store minted coins in a Vault<T> at ADMIN
        move_to(admin, Vault<T> { balance: coins_minted });
        // Capabilities logic
        let account_addr = signer::address_of(admin);
        coin::destroy_burn_cap<T>(burn_cap);
        coin::destroy_freeze_cap<T>(freeze_cap);
        coin::destroy_mint_cap<T>(mint_cap);
        // If you want to remove or transfer the capabilities, do it properly:
        // e.g., move_from<Capabilities<T>>(admin)
    }

    // User coin registration
    public entry fun register<T>(user: &signer) {
        managed_coin::register<T>(user);
    }

    //public native deposit
    public entry fun deposit<T>(banker: &signer, amount: u64) acquires Vault {
        let who = signer::address_of(banker);

        let vault = borrow_global_mut<Vault<T>>(@dev);

        let coins = coin::withdraw<T>(banker, amount);
        coin::merge(&mut vault.balance, coins);
    }

    // Convenience transfer (standard user transfer)
    public entry fun transfer<T>(sender: &signer, recipient: address, amount: u64) {
        coin::transfer<T>(sender, recipient, amount);
    }

// === HELPER FUNCTIONS === //
    // Vault-controlled flows (only validators can use)

    public fun withdraw_to<T>(banker: &signer, cap: Permission, recipient: address, amount: u64)acquires Vault {
        let who = signer::address_of(banker);
        //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);

        let vault = borrow_global_mut<Vault<T>>(@dev);
        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit<T>(recipient, coins);
    }

    public fun extract_to<T>(banker: &signer, cap: Permission, recipient: address, amount: u64): Coin<T> acquires Vault {
        let who = signer::address_of(banker);
        //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);

        let vault = borrow_global_mut<Vault<T>>(@dev);
        coin::extract(&mut vault.balance, amount)
    }

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
    public fun supply<T>(): u64 acquires Vault {
        let vault = borrow_global<Vault<T>>(@dev);
        18446744073709551615 - (coin::value(&vault.balance))
    }
}
