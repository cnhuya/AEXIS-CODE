module dev::AexisBridgeStorageV50 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use std:hash;
    use std::bcs;
    use aptos_std::from_bcs;


    const ERROR_NO_WALLET_REQUEST: u64 = 1;


    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------



    struct Counter has key{
        count: u128
    }

    struct WithnessStore has key {
        store: table::Table<address, Withness>
    } 

    struct WitnessBody has key {
        address: vector<u8>,
        ID: vector<u8>,
        seed: vector<u8>
    }

    struct Witness has key{
        obj: vector<u8>
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);
        if (!exists<Counter>(@dev)) {
            move_to(admin,Counter { count: u128 });
        };
    }

    public fun make_storage(addr: &signer, seed: vector<u8>): WitnessBody acquires Counter{
        let counter = borrow_global_mut<Counter>(@dev);
        counter.count = counter.count + 1;
        return WitnessBody {address: bcs::to_bytes(&signer::address_of(addr)), id: bcs::to_bytes(&counter.count), seed: seed}
    }

    public entry fun make_unique_storage(addr: &signer, seed: vector<u8>) acquires Counter {
       move_to(addr, Witness { obj: convert_to_witness(&make_storage(addr, seed)) });
    }

    public fun convert_to_witness(body: &WitnessBody): Witness{
        return Witness {obj: hash::sha3_256(vect)}
    }

    public fun unwrap_witness(witness: &Witness): vector<u8>{
        return withness.obj
    }

    public fun transfer_witness(witness: &mut Witness){
        move_from()
        move_to
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