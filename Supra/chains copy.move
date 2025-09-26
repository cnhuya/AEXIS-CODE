module dev::AexisChainsV32 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info;
    use std::table;
    use std::timestamp;
    use aptos_std::from_bcs;
    use supra_framework::event;
    use dev::AexisChainTypesV32::{Supra, Sui, Base};

    /// Admin address constant
    const ADMIN: address = @dev; // <-- replace with real admin address

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_VALIDATOR_IS_ALREADY_ALLOWED: u64 = 3;
    const ERROR_INVALID_CHAIN_TYPE_ARGUMENT: u64 = 4;
    const ERROR_CHAIN_ALREADY_REGISTERED: u64 = 5;
    const ERROR_NOT_VALIDATOR: u64 = 6;
    const ERROR_DUPLICATE_EVENT: u64 = 7;
    const ERROR_INVALID_BATCH_REGISTER_EVENT_ARG_EQUALS: u64 = 8;

    struct ConfiguratorCap has store, key { }


    struct DepositEvent has store, key {}
    struct RequestUnlockEvent has store, key {}
    struct UnlockEvent has store, key {}



   /// counting how many times the message was "validated"
   /// If lets say it was "validated" total of 5 times succesfully, the 6th times will mote if from here
   /// to chain storage
    struct Pending<phantom T> has key {
        deposits: table::Table<vector<u8>, u8>,
        request_unlocks: table::Table<vector<u8>, u8>,
        unlocks: table::Table<vector<u8>, u8>,
    }

    struct EventType<phantom E> has store, drop, key {
        native_tx_hash: vector<u8>,
        validator: vector<u8>,
        user: vector<u8>,
        amount: u64,
    }

    struct Chain<phantom T> has key {
        id: u8,
        block_time: u64,
        quarum: u8,
        name: String,
        symbol: String,
        validators: vector<vector<u8>>,
        deposits: table::Table<u64, vector<EventType<DepositEvent>>>,
        request_unlocks: table::Table<u64, vector<EventType<RequestUnlockEvent>>>,
        unlocks: table::Table<u64, vector<EventType<UnlockEvent>>>,
    }


    #[event]
    struct EventRegistered has copy, drop, store {
        validator: address,
        chain_type: String,
        type: String,
        recipient: vector<u8>,
        amount: u64
    }

    fun init_module(admin: &signer) {
        if (!exists<ConfiguratorCap>(ADMIN)) {
            move_to(admin, ConfiguratorCap {});
        };
    }

    public entry fun register_chain<T>(admin: &signer, id: u8, block_time: u64, quarum: u8 name: String, symbol: String) {
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);
        assert!(!exists<Chain<T>>(signer::address_of(admin)), ERROR_CHAIN_ALREADY_REGISTERED);

        let deposits_table = table::new<u64, vector<EventType<DepositEvent>>>();
        let request_unlocks_table = table::new<u64, vector<EventType<RequestUnlockEvent>>>();
        let unlocks_table = table::new<u64, vector<EventType<UnlockEvent>>>();

        let chain = Chain<T> { 
            id, 
            block_time, 
            quarum,
            name, 
            symbol, 
            validators: vector::empty<vector<u8>>(),  
            deposits: deposits_table,
            request_unlocks: request_unlocks_table,
            unlocks: unlocks_table,
        };

        let _deposits_table = table::new<vector<u8>, u8>();
        let _request_unlocks_table = table::new<vector<u8>, u8>();
        let _unlocks_table = table::new<vector<u8>, u8>();

        let pending = Pending<T> { 
            deposits: _deposits_table,
            request_unlocks: _request_unlocks_table,
            unlocks: _unlocks_table,
        };


        move_to(admin, chain);
        move_to(admin, pending);
    }


    ///
    /// TO DO
    /// 
    /// Implement manual event registration, bridge aggregrator would then check the tx hash offchain and emit new event registration,
    /// unless all asserts are passed (transaction type is allowed (package,module,function...) or check txs if allowed in certain blockchains)
    /// 

    public entry fun batch_register_event<T, E>(admin: &signer, native_tx_hash: vector<vector<u8>>, validator: vector<u8>, user: vector<vector<u8>>, amount: vector<u64>) acquires Chain{
        assert!(vector::length(&native_tx_hash) == vector::length(&user) && vector::length(&user) == vector::length(&amount), ERROR_INVALID_BATCH_REGISTER_EVENT_ARG_EQUALS);
        let len = vector::length(&native_tx_hash);
        while(len>0){
            register_event<T,E>(admin, *vector::borrow(&native_tx_hash, len-1), validator, *vector::borrow(&user, len-1), *vector::borrow(&amount, len-1));
            len = len-1;
        };
    }

    public entry fun register_event<T, E>(admin: &signer, native_tx_hash: vector<u8>, validator: vector<u8>, user: vector<u8>, amount: u64,) acquires Chain, Pending {
        assert!(vector::contains(&get_supra_bankers(), &signer::address_of(admin)), ERROR_NOT_VALIDATOR);

        let chain = borrow_global_mut<Chain<T>>(signer::address_of(admin));
        let pending = borrow_global_mut<Pending<T>>(signer::address_of(admin));

        let timestamp = timestamp::now_seconds();

        // Pass chain directly (mutable reference) no & needed

        // This is checked offchain aswell, to help eliminate aborted transactions to save on bandwith
        assert!(!is_tx_registered<T, E>(chain, &native_tx_hash), ERROR_DUPLICATE_EVENT);


        let epoch_key = timestamp / 86400;

        if (type_info::type_name<E>() == type_info::type_name<DepositEvent>()) {
            let event = EventType<DepositEvent> { native_tx_hash, validator, user, amount };

            if (!table::contains(&chain.deposits, epoch_key)) {
                table::add(&mut chain.deposits, epoch_key, vector::empty<EventType<DepositEvent>>());
            };

            let vec = table::borrow_mut(&mut chain.deposits, epoch_key);
            vector::push_back(vec, event);

        } else if (type_info::type_name<E>() == type_info::type_name<RequestUnlockEvent>()) {
            let event = EventType<RequestUnlockEvent> { native_tx_hash, validator, user, amount };

            if (!table::contains(&chain.request_unlocks, epoch_key)) {
                table::add(&mut chain.request_unlocks, epoch_key, vector::empty<EventType<RequestUnlockEvent>>());
            };

            let vec = table::borrow_mut(&mut chain.request_unlocks, epoch_key);
            vector::push_back(vec, event);

        } else if (type_info::type_name<E>() == type_info::type_name<UnlockEvent>()) {
            let event = EventType<UnlockEvent> { native_tx_hash, validator, user, amount };

            if (!table::contains(&chain.unlocks, epoch_key)) {
                table::add(&mut chain.unlocks, epoch_key, vector::empty<EventType<UnlockEvent>>());
            };

            let vec = table::borrow_mut(&mut chain.unlocks, epoch_key);
            vector::push_back(vec, event);
        }
    }

    // In the future allow anyone to add validator if they stake enough coins
    public entry fun allow_validator<T: store>(admin: &signer, validator: vector<u8>) acquires ConfiguratorCap, Chain {
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

    ///
    /// VIEW
    /// 

    #[view]
    public fun get_chain_validators<T>(): vector<vector<u8>> acquires Chain {
        let chain = borrow_global<Chain<T>>(ADMIN);
        chain.validators
    }

    ///
    /// HELPER
    /// 
    
    public fun batch_is_tx_registered<T, E>(chain: &mut Chain<T>,txs: &vector<vector<u8>>): v {
        let chain = borrow_global_mut<Chain<T>>(ADMIN);
        let len = vector::length(&txs);
        while(len>0){
            let result = is_tx_registered(chain, vector::borrow(&txs, len-1));
        }
        is_tx_registered(chain, vector::borrow(&txs, len-1));

        
    public fun is_tx_registered<T, E>(chain: &mut Chain<T>,native_tx_hash: &vector<u8>): bool {
        let timestamp = timestamp::now_seconds();
        let epoch_key = timestamp / 86400;

        if (type_info::type_name<E>() == type_info::type_name<DepositEvent>()) {
            if (!table::contains(&chain.deposits, epoch_key)) {
                return false;
            };
            let vec = table::borrow_mut(&mut chain.deposits, epoch_key);
            let len = vector::length(vec);
            let i = 0;
            while (i < len) {
                let event = vector::borrow(vec, i);
                if (event.native_tx_hash == *native_tx_hash) {
                    return true;
                };
                i = i + 1;
            };
            false

        } else if (type_info::type_name<E>() == type_info::type_name<RequestUnlockEvent>()) {
            if (!table::contains(&chain.request_unlocks, epoch_key)) {
                return false;
            };
            let vec = table::borrow_mut(&mut chain.request_unlocks, epoch_key);
            let len = vector::length(vec);
            let i = 0;
            while (i < len) {
                let event = vector::borrow(vec, i);
                if (event.native_tx_hash == *native_tx_hash) {
                    return true;
                };
                i = i + 1;
            };
            false

        } else if (type_info::type_name<E>() == type_info::type_name<UnlockEvent>()) {
            if (!table::contains(&chain.unlocks, epoch_key)) {
                return false;
            };
            let vec = table::borrow_mut(&mut chain.unlocks, epoch_key);
            let len = vector::length(vec);
            let i = 0;
            while (i < len) {
                let event = vector::borrow(vec, i);
                if (event.native_tx_hash == *native_tx_hash) {
                    return true;
                };
                i = i + 1;
            };
            false
        } else {
            false
        }
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

      fun copy_range(v: &vector<u8>, start: u64, len: u64): vector<u8> {
            let out = vector::empty<u8>();
            let i = 0;
            while (i < len) {
                let b_ref = vector::borrow(v, start + i);
                vector::push_back(&mut out, *b_ref);
                i = i + 1;
            };
            out
        }

    // or add the type to argument
    public fun deserialize_message<E>(message: &vector<u8>): EventType<E> {
        let len = vector::length(message);
        assert!(len >= 104, EINVALID_SIGNATURE);

        let native_tx_hash = from_bcs::to_address(copy_range(message, 0, 32)); // tx hash is 32 bytes
        let validator_addr = from_bcs::to_address(copy_range(message, 32, 64)); // addresses are 32 bytes
        let user_addr = from_bcs::to_address(copy_range(message, 64, 96)); // addresses are 32 bytes
        let value_num = from_bcs::to_u64(copy_range(message, 96, 100)); // u32 is 8 bytes

        EventType<E> {
            native_tx_hash:native_tx_hash,
            validator: validator_addr,
            user: user_addr,
            amount: value_num,
        }
    }
}
