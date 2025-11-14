module dev::QiaraAutoRegistry {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use std:timestamp;
    use std::table;

    use dev::QiaraStorageV29::{Self as storage,};
    use dev::QiaraCapabilitiesV29::{Self as capabilities,};

// === ERRORS === //
    const ERROR_DURATION_TOO_LONG: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_DELETIONS: u64 = 2;

/// === INIT ===
    fun init_module(admin: &signer) {
        if (!exists<AutomatedTransactionsTracker>(@dev)) {
            move_to(admin, AutomatedTransactionsTracker { 
                tracker: table::new<address, Table<u64, u64>>() 
            });
        };
        if (!exists<AutomatedTransactionsCounter>(@dev)) {
            move_to(admin, AutomatedTransactionsCounter { 
                counter: table::new<address, u64>(),
                expired: table::new<address, u64>() 
            });
        };
    }

/// === STRUCTS ===
     struct Index has key, store {
        i:u:64,
        expiry: u64,
    }
 
    struct AutomatedTransactionsTracker has key {
        tracker: Table<address, Table<u64, u64>>
    }

    struct AutomatedTransactionsCounter has key {
        counter: Table<address, u64>
        expired: Table<address, u64>
    }

/// === FUNCTIONS ===
    public fun register_automated_transaction(address: address, i: u64, duration: u64) acquires AutomatedTransactionsTracker, AutomatedTransactionsCounter {
        assert!(storage::expect_u64(storage::viewConstant(utf8(b"QiaraAuto"), utf8(b"MAX_DURATION"))),ERROR_DURATION_TOO_LONG);
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
        let counter_bookshelf = borrow_global_mut<AutomatedTransactionsCounter>(@dev);
        
        // Initialize user counter if not exists
        if (!table::contains(&counter_bookshelf.counter, address)) {
            table::add(&mut counter_bookshelf.counter, address, 0);
        };
        
        // Get user's current counter
        let user_counter = table::borrow_mut(&mut counter_bookshelf.counter, address);
        
        // Initialize user's tracker table if not exists
        if (!table::contains(&tracker_bookshelf.tracker, address)) {
            table::add(&mut tracker_bookshelf.tracker, address, table::new<u64, Index>());
        };
        
        // Get user's tracker table
        let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, address);
        
        // Register the automation with current counter
        table::add(user_tracker, *user_counter, Index: {i:i, expiry: timestamp::now_seconds()+duration});
        
        // Increment the counter for next automation
        *user_counter = *user_counter + 1;
    }

    public fun delete_expired_automated_transactions(address: address) acquires AutomatedTransactionsTracker, AutomatedTransactionsCounter {
        assert!(!capabilities::assert_wallet_capability(signer::address_of(sender), utf8(b"QiaraAuto"), utf8(b"EXECUTE_AUTO_DELETIONS")), ERROR_NOT_AUTHORIZED_FOR_DELETIONS);
        
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
        let counter_bookshelf = borrow_global_mut<AutomatedTransactionsCounter>(@dev);

        // Check if user exists in counter table
        if (!table::contains(&counter_bookshelf.counter, address)) {
            return;
        };

        // Check if user exists in tracker table
        if (!table::contains(&tracker_bookshelf.tracker, address)) {
            return;
        };

        let user_counter = table::borrow(&counter_bookshelf.counter, address);
        let current_count = *user_counter;
        
        // Initialize expired counter if not exists
        if (!table::contains(&counter_bookshelf.expired, address)) {
            table::add(&mut counter_bookshelf.expired, address, 0);
        };
        let user_deleted = table::borrow_mut(&mut counter_bookshelf.expired, address);
        
        let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, address);
        
        // Iterate backwards to avoid index issues when removing
        let i = current_count;
        while (i > 0) {
            // Check if this automation ID exists in user's tracker
            if (table::contains(user_tracker, i)) {
                let automation = table::borrow(user_tracker, i);
                
                // Check if expired (assuming your Automation struct has expiry field)
                if (automation.expiry <= timestamp::now_seconds()) {
                    // Remove the expired automation
                    table::remove(user_tracker, i);
                    *user_deleted = *user_deleted + 1;
                };
            };
            i = i - 1;
        };
    }
}
