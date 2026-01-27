module dev::zkbalV1{
    use std::vector;
    use std::signer;
    use supra_framework::event;
    use std::timestamp;
    use std::string::{Self as String, String, utf8};
    // --- CUSTOM SERIALIZATION CONSTANTS ---
    // User requirement: u256 from ZK should be treated as Little Endian bytes
    

// === EVENTS === //
    #[event]
    struct TestEvent has copy, drop, store {
        address: address,
        token: String,
        chain: String,
        isDeposit: bool,
        storageID: u64,
        amount: u256,
        balance: u256,
        time: u64
    }



    const ERROR_NOT_ADMIN: u64 = 1;

    // === INIT === //
    fun init_module(admin: &signer) {

    }

    public entry fun emit_test_event(addr: address,token: String,chain: String,isDeposit: bool,storageID: u64,amount: u256,balance: u256,) {
        let time = timestamp::now_seconds();
            event::emit(TestEvent {
                address: addr,
                token: token,
                chain: chain,
                isDeposit: isDeposit,
                storageID: storageID,
                amount: amount,
                balance: balance,
                time: time
            });
    }

}