module dev::AexisBridgeV2 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info;
    use aptos_std::from_bcs;
    use supra_framework::event;
    use dev::AexisChainTypes::{Supra, Sui, Base};

    /// Admin address constant
    const ADMIN: address = @dev; // <-- replace with real admin address

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_VALIDATOR_IS_ALREADY_ALLOWED: u64 = 3;
    const ERROR_INVALID_CHAIN_TYPE_ARGUMENT: u64 = 4;
    const ERROR_CHAIN_ALREADY_REGISTERED: u64 = 5;

    struct ConfiguratorCap has store, key { }

    struct Chain<phantom T> has key {
        id: u8,
        block_time: u64,
        name: String,
        symbol: String,
        validators: vector<vector<u8>>,
        transactions: vector<vector<u8>>,
    }


    fun init_module(admin: &signer) {
        if (!exists<ConfiguratorCap>(ADMIN)) {
            move_to(admin, ConfiguratorCap {});
        };
    }

    public entry fun register_chain<T>(admin: &signer, id: u8, block_time: u64, name: String, symbol: String){
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);
        assert!(!exists<Chain<T>>(signer::address_of(admin)), ERROR_CHAIN_ALREADY_REGISTERED);

        let chain = Chain<T> { id, block_time, name, symbol, validators: vector::empty<vector<u8>>(),  transactions: vector::empty<vector<u8>>() };
        move_to(admin, chain);
    }

    // in the future allow anyone to add validator if they stake enough coins
    public fun allow_validator<T: store>(admin: &signer, validator: vector<u8>) acquires ConfiguratorCap, Chain {
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);

        let _cap = borrow_global<ConfiguratorCap>(signer::address_of(admin));

        let chain = borrow_global_mut<Chain<T>>(ADMIN);
        let i = 0;
        let validators_len = vector::length(&chain.validators);
        while (i < validators_len) {
            let existing = vector::borrow(&chain.validators, i);
            assert!(*existing != validator, ERROR_VALIDATOR_IS_ALREADY_ALLOWED);
            i = i + 1;
        };
        vector::push_back(&mut chain.validators, validator);
    }



    public entry fun set_block_time<T>(admin: &signer, new_time: u64) acquires Chain{
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);

        let chain = borrow_global_mut<Chain<T>>(ADMIN);
        chain.block_time = new_time;
    }


    #[view]
    public fun get_chain_validators<T>(): vector<vector<u8>> acquires Chain {
        let chain = borrow_global<Chain<T>>(ADMIN);
        chain.validators
    }
    
    public fun get_supra_bankers(): vector<address> acquires Chain {
        let chain = borrow_global_mut<Chain<Supra>>(ADMIN);
        let len = vector::length(&chain.validators);
        let vect = vector::empty<address>();
        let i = 0;
        while (i < len) {
            let validator = vector::borrow(&chain.validators, i);
            vector::push_back(&mut vect, from_bcs::to_address(*validator));
            i = i + 1;
        };
        vect
    }
}
