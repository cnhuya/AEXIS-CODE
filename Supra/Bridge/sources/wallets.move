module dev::AexisWalletsV1 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use dev::AexisChainTypesV1::{Supra, Sui, Base};

    const ADMIN: address = @dev;

    const ERROR_NO_WALLET_REQUEST: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_WALLET_ALREADY_REQUESTED: u64 = 3;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    /// Each user can register wallets from other chains
    struct Wallets<phantom T> has key {
        addresses: vector<vector<u8>>, // external addresses
    }

    /// Admin stores pending link requests: user -> list of wallets
    struct PendingWallets has key {
        requests: table::Table<address, vector<BridgedWallet>>,
    }

    struct BridgedWallet has copy, drop, store {
        chain_id: u8,
        address: vector<u8>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == ADMIN, 1);
        if (!exists<PendingWallets>(ADMIN)) {
            move_to(
                admin,
                PendingWallets { requests: table::new<address, vector<BridgedWallet>>() }
            );
        };
    }

    public entry fun make_request(user: &signer, destination_address: address, chain_id: u8, address: vector<u8>) acquires PendingWallets {
        let addr = signer::address_of(user);
        let pending = borrow_global_mut<PendingWallets>(ADMIN);

        if (!table::contains(&pending.requests, destination_address)) {
            table::add(&mut pending.requests, destination_address, vector::empty<BridgedWallet>());
        };

        let requests = table::borrow_mut(&mut pending.requests, destination_address);
        assert!(!vector::contains(requests, &BridgedWallet{chain_id, address}), ERROR_WALLET_ALREADY_REQUESTED);
        vector::push_back(requests, BridgedWallet{chain_id, address});
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