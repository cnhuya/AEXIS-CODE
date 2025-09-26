module 0x0::SUIBITCOIN_VAULT;
    use sui::coin::{Coin, SUIBITCOIN};
    use sui::transfer;
    use

    /// Per-user vault object that holds a single coin deposit
    public struct UserVault has key {
        owner: address,
        coin: Coin<SUIBITCOIN>,
    }

    /// Admin object
    public struct Admin has key {
        addr: address,
    }

    /// Create a new admin object
    public fun create_admin(addr: address): Admin {
        Admin { addr }
    }

    /// User deposits a coin into a new UserVault
    public fun deposit(user: &signer, coin: Coin<SUIBITCOIN>): UserVault {
        let addr = signer::address_of(user);
        UserVault { owner: addr, coin }
    }

    /// Admin unlocks a user's vault and transfers the coin to a recipient
    public fun unlock(admin: &Admin, vault: UserVault, recipient: address) {
        assert!(signer::address_of(&admin.addr) == admin.addr, 1); // simple admin check
        let coin = vault.coin;
        transfer::public_transfer(coin, recipient);
    }

    /// Get balance in a UserVault
    public fun balance(vault: &UserVault): u64 {
        Coin::value(&vault.coin)
    }
