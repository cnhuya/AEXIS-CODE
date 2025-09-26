module dev::test123 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};

    // ----------------------------------------------------------------
    // Module init: set up all coins and their vaults under ADMIN
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {

    }

    // ----------------------------------------------------------------
    // Initialize a single coin T and create a vault with full u64::MAX
    // ----------------------------------------------------------------

    public entry fun test(a: vector<u8>, b: vector<u8>) {
        let d = vector::length(&a);
        let e = vector::length(&b);
    }
}
