module dev::AexisBaseCoinsDeployerV2 {
    use std::signer;
    use std::option;
    use std::vector;
    use supra_framework::coin;
    use supra_framework::managed_coin;
    use std::string::{Self as String, String};

    const ADMIN: address = @dev;

    // Coin types
    struct AexisEthereum has drop, store, key {}
    struct AexisUSDC has drop, store, key {}


    // --------------------------
    // Initialize coins
    // --------------------------
    public entry fun init_coin<T: store>(admin: &signer,name: String,symbol: String,decimals: u8) {
        managed_coin::initialize<T>(
            admin,
            *String::bytes(&name),
            *String::bytes(&symbol),
            decimals,
            true
        );

        coin::register<T>(admin);
    }

    // --------------------------
    // User coin registration
    // --------------------------
    public entry fun register<T>(user: &signer) {
        managed_coin::register<T>(user);
    }

    // --------------------------
    // Mint / burn / transfer
    // --------------------------
    public entry fun mint_to<T>(admin: &signer, dst_addr: address, amount: u64) {
        managed_coin::mint<T>(admin, dst_addr, amount);
    }

    public entry fun burn_from_admin<T>(admin: &signer, amount: u64) {
        managed_coin::burn<T>(admin, amount);
    }

    public entry fun burn_all<T>(admin: &signer) {
        managed_coin::burn<T>(admin, balance_of<T>(signer::address_of(admin)));
    }

    public entry fun transfer<T>(sender: &signer, recipient: address, amount: u64) {
        coin::transfer<T>(sender, recipient, amount);
    }

    public fun balance_of<T>(addr: address): u64 {
        coin::balance<T>(addr)
    }

    public fun supply<T>(): option::Option<u128> {
        coin::supply<T>()
    }

}
