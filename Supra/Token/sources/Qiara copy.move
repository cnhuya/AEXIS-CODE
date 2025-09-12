module dev::Qiara {
    use std::signer;
    use std::option;
    use std::vector;
    use std::timestamp;
    use supra_framework::coin;
    use supra_framework::managed_coin;
    use std::string::{Self as String, String};

    const ADMIN: address = @dev;

    // Coin types
    struct Qiara has drop, store, key {}

    struct Fees has drop, store, key{
        burn_fee: u16,
        treasury_fee: u16,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module<T: store>(admin: &signer) {
        managed_coin::initialize<T>(
            admin,
            utf8(b"Qiara Token"),
            utf8(b"Qiara"),
            8,
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
    fun mint_to<T>(admin: &signer, dst_addr: address, amount: u64) {
        managed_coin::mint<T>(admin, dst_addr, amount);
    }

    public entry fun burn_all<T>(admin: &signer) {
        managed_coin::burn<T>(admin, balance_of<T>(signer::address_of(admin)));
    }

    public entry fun transfer<T>(sender: &signer, recipient: address, amount: u64) acquires Fees {
        let fees = borrow_global<Fees>(ADMIN);
        let fee_amount = amount * ((fees.burn_fee + fees.treasury_fee) * amount);
        coin::transfer<T>(sender, recipient, amount-fee_amount);
        coin::transfer<T>(sender, treasury, fee_amount);
    }

    public fun balance_of<T>(addr: address): u64 {
        coin::balance<T>(addr)
    }

    public fun supply<T>(): option::Option<u128> {
        coin::supply<T>()
    }

    public fun fees(): option::Option<u128> {
        coin::supply<T>()
    }

}
