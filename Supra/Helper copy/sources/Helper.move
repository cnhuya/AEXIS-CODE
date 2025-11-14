module dev::qiara_auto_incr {
    use supra_framework::timestamp;
    use supra_framework::event;
    use supra_framework::account;
    use std::signer;
    use std::error;

    struct Counter has key {
        value: u64,
        last_increment_time: u64,
        total_increments: u64,
    }
    /// Event emitted when counter is incremented
    #[event]
    struct CounterIncremented has drop, store {
        old_value: u64,
        new_value: u64,
        timestamp: u64,
        total_increments: u64,
    }
    /// Error codes
    const E_COUNTER_NOT_INITIALIZED: u64 = 1;
    const E_TOO_EARLY_FOR_INCREMENT: u64 = 2;

    fun init_module(account: &signer) {
        let account_addr = signer::address_of(account);
    
        assert!(!exists<Counter>(account_addr), error::already_exists(E_COUNTER_NOT_INITIALIZED));
        let current_time = timestamp::now_seconds();
        
        move_to(account, Counter {
            value: 0,
            last_increment_time: current_time,
            total_increments: 0,
        });
    }
    public entry fun auto_increment(account: &signer) acquires Counter {
        let account_addr = signer::address_of(account);

        assert!(exists<Counter>(account_addr), error::not_found(E_COUNTER_NOT_INITIALIZED));
        
        let counter = borrow_global_mut<Counter>(account_addr);
        let current_time = timestamp::now_seconds();
        let old_value = counter.value;
        counter.value = counter.value + 1;
        counter.last_increment_time = current_time;
        counter.total_increments = counter.total_increments + 1;
        event::emit(CounterIncremented {
            old_value,
            new_value: counter.value,
            timestamp: current_time,
            total_increments: counter.total_increments,
        });
    }

    /// View function to get current counter value
    #[view]
    public fun get_counter_value(account_addr: address): u64 acquires Counter {
        assert!(exists<Counter>(account_addr), error::not_found(E_COUNTER_NOT_INITIALIZED));
        borrow_global<Counter>(account_addr).value
    }
    /// View function to get detailed counter info
    #[view]
    public fun get_counter_info(account_addr: address): (u64, u64, u64) acquires Counter {
        assert!(exists<Counter>(account_addr), error::not_found(E_COUNTER_NOT_INITIALIZED));
        let counter = borrow_global<Counter>(account_addr);
        (counter.value, counter.last_increment_time, counter.total_increments)
    }

    /// Manual increment function for testing (optional)
    public entry fun manual_increment(account: &signer) acquires Counter {
        auto_increment(account);
    }
    /// Reset counter (for testing purposes)
    public entry fun reset_counter(account: &signer) acquires Counter {
        let account_addr = signer::address_of(account);
        assert!(exists<Counter>(account_addr), error::not_found(E_COUNTER_NOT_INITIALIZED));
        
        let counter = borrow_global_mut<Counter>(account_addr);
        counter.value = 0;
        counter.last_increment_time = timestamp::now_seconds();
        counter.total_increments = 0;
    }

    // Test functions
    #[test_only]
    #[test(account = @0x123)]
    public entry fun test_counter_initialization(account: signer) acquires Counter {
        let account_addr = signer::address_of(&account);
        account::create_account_for_test(account_addr);
        // Initialize counter
        init_module(&account);        
        // Check initial value
        assert!(get_counter_value(account_addr) == 0, 1);
        // Test increment
        manual_increment(&account);
        assert!(get_counter_value(account_addr) == 1, 2);
        // Test another increment
        manual_increment(&account);
        assert!(get_counter_value(account_addr) == 2, 3);
    }
}