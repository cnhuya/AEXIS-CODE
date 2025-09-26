module dev::AexisWalletsV50 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use dev::AexisChainTypesV2::{Supra, Sui, Base};
    use dev::QiaraTestV27 as Qiara;

    const ADMIN: address = @dev;

    const ERROR_NO_WALLET_REQUEST: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_WALLET_ALREADY_REQUESTED: u64 = 3;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------
    struct QiaraVault has key, store {
        balance: Object<FungibleStore>, // qiara coin reserve
    }

    struct Staker has key, store{
        balance: u64,
        avg_time: u64,
    } 
    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {

    }

    public entry fun stake(user: &signer, amount: u64) acquires QiaraVault {
        let vault = borrow_global_mut<QiaraVault>(ADMIN);

        if (!exists<Staker>(signer::address_of(user))) {
            move_to(user,Staker {balance: amount, avg_time: timestamp::now_seconds() });
        };

        Qiara::withdraw_from_store(sender, vault.balance, amount);

    }

    public entry fun unstake(user: &signer, amount: u64) acquires QiaraVault {
        let vault = borrow_global_mut<QiaraVault>(ADMIN);

        if (!exists<Staker>(signer::address_of(user))) {
            move_to(user,Staker {balance: amount, avg_time: timestamp::now_seconds() });
        };

        Qiara::withdraw_from_store(sender, vault.balance, amount);

    }

    // ----------------------------------------------------------------
    // User approval of wallet requests
    // ----------------------------------------------------------------
    /// Called by the user to approve a wallet request proposed by the bridge.
    public entry fun allow_wallet(user: &signer, chain_id: u8, address: vector<u8>) acquires PendingWallets, Wallets {
        let addr = signer::address_of(user);
        let pending = borrow_global_mut<PendingWallets>(ADMIN);

        // User must have a pending request
        if (!table::contains(&pending.requests, addr)) {
            abort ERROR_NO_WALLET_REQUEST;
        };

        let user_requests = table::borrow_mut(&mut pending.requests, addr);

        let i = 0;
        let len = vector::length(user_requests);
        while (i < len) {
            let req_ref = vector::borrow(user_requests, i);
            if (req_ref.chain_id == chain_id && req_ref.address == address) {
                // Found the matching pending request  approve it
                vector::remove(user_requests, i);
                finalize_binding(user, chain_id, address);
                return;
            };
            i = i + 1;
        };

        // If no matching request, abort
        abort ERROR_NO_WALLET_REQUEST;
    }

    // ----------------------------------------------------------------
    // Internal binding
    // ----------------------------------------------------------------
    fun finalize_binding(user: &signer, chain_id: u8, wallet: vector<u8>) acquires Wallets {
        let addr = signer::address_of(user);

        // Ensure Wallets<Sui> and Wallets<Base> exist
        if (!exists<Wallets<Sui>>(addr)) {
            move_to(user, Wallets<Sui>{ addresses: vector::empty<vector<u8>>() });
        };
        if (!exists<Wallets<Base>>(addr)) {
            move_to(user, Wallets<Base>{ addresses: vector::empty<vector<u8>>() });
        };
        if (!exists<Wallets<Supra>>(addr)) {
            move_to(user, Wallets<Supra>{ addresses: vector::empty<vector<u8>>() });
        };

        // Bind based on chain_id
        if (chain_id == 1) {
            let w = borrow_global_mut<Wallets<Sui>>(addr);
            if (!vector::contains(&w.addresses, &wallet)) {
                vector::push_back(&mut w.addresses, wallet);
            };
        } else if (chain_id == 2) {
            let w = borrow_global_mut<Wallets<Base>>(addr);
            if (!vector::contains(&w.addresses, &wallet)) {
                vector::push_back(&mut w.addresses, wallet);
            };
        } else if (chain_id == 3) {
            let w = borrow_global_mut<Wallets<Supra>>(addr);
            if (!vector::contains(&w.addresses, &wallet)) {
                vector::push_back(&mut w.addresses, wallet);
            };
        } else {
            abort ERROR_INVALID_CHAIN_ID;
        };
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------
    #[view]
    public fun view_wallets<T>(addr: address): vector<vector<u8>> acquires Wallets {
        let wallet_struct = borrow_global<Wallets<T>>(addr);
        wallet_struct.addresses
    }

    #[view]
    public fun view_requests_for_address(addr: address): vector<BridgedWallet> acquires PendingWallets {
        let pending = borrow_global<PendingWallets>(ADMIN);
        if (table::contains(&pending.requests, addr)) {
            let user_requests = table::borrow(&pending.requests, addr);
            *user_requests
        } else {
            abort ERROR_NO_WALLET_REQUEST
        }
    }
}