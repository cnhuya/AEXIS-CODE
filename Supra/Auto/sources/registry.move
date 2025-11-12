module dev::QiaraAutoRegistry {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use std::timestamp;
    use std::table::{Self, Table};
    use std::signer;
    use dev::QiaraStorageV30::{Self as storage,};
    use dev::QiaraCapabilitiesV30::{Self as capabilities,};

// === ERRORS === //
    const ERROR_DURATION_TOO_LONG: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_DELETIONS: u64 = 2;
    const ERROR_AUTOMATED_TRANSACTION_WITH_THIS_ID_ALREADY_EXISTS: u64 = 3;

/// === INIT ===
    fun init_module(admin: &signer) {
        if (!exists<AutomatedTransactionsTracker>(@dev)) {
            move_to(admin, AutomatedTransactionsTracker { 
                tracker: table::new<address, Table<String, Index>>() 
            });
        };
    }

/// === STRUCTS ===
     struct Index has copy, drop, key, store {
        i: u64,
        expiry: u64,
    }
 
    struct AutomatedTransactionsTracker has key {
        tracker: Table<address, Table<String, Index>>
    }


/// === FUNCTIONS ===
    public fun register_automated_transaction(address: address, i: u64, duration: u64, uid: String) acquires AutomatedTransactionsTracker {
        assert!(storage::expect_u64(storage::viewConstant(utf8(b"QiaraAuto"), utf8(b"MAX_DURATION"))) >= duration,ERROR_DURATION_TOO_LONG);
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
        
        // Initialize user's tracker table if not exists
        if (!table::contains(&tracker_bookshelf.tracker, address)) {
            table::add(&mut tracker_bookshelf.tracker, address, table::new<String, Index>());
        };
        
        // Get user's tracker table
        
        if (!table::contains(table::borrow(&mut tracker_bookshelf.tracker, address), uid)) {
          let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, address);
          table::add(user_tracker, uid, Index {i:i, expiry: timestamp::now_seconds()+duration});
        } else {
            abort ERROR_AUTOMATED_TRANSACTION_WITH_THIS_ID_ALREADY_EXISTS;
        }
    }

    public fun delete_expired_automated_transactions(signer: &signer, address: address, uids: vector<String>) acquires AutomatedTransactionsTracker {
        assert!(!capabilities::assert_wallet_capability(signer::address_of(signer), utf8(b"QiaraAuto"), utf8(b"EXECUTE_AUTO_DELETIONS")), ERROR_NOT_AUTHORIZED_FOR_DELETIONS);
        
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);

        if (!table::contains(&tracker_bookshelf.tracker, address)) {
            return;
        };
        
        let len = vector::length(&uids);
        while(len>0){
            let uid = *vector::borrow(&uids, len-1);
            if (table::contains(table::borrow(&mut tracker_bookshelf.tracker, address), uid)) {
                let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, address);
                let automation = table::borrow(user_tracker, uid);
                    
                if (automation.expiry <= timestamp::now_seconds()) {
                    table::remove(user_tracker, uid);
                };
                len=len-1;
            };
        }
    }

    public fun stop_automated_transaction(address: address, uid: String) acquires AutomatedTransactionsTracker {
        
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);

        if (!table::contains(&tracker_bookshelf.tracker, address)) {
            return;
        };
        
        let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, address);
        
        if (table::contains(user_tracker, uid)) {
            let automation = table::borrow_mut(user_tracker, uid);
            automation.i = 0;
        };
    }

    public fun validate_automated_transaction(address: address, uid: String): bool acquires AutomatedTransactionsTracker{
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);

        if (!table::contains(&tracker_bookshelf.tracker, address)) {
           return false
        };

        if (!table::contains(table::borrow(&mut tracker_bookshelf.tracker, address), uid)) {
            return false
        } else {
            let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, address);
            let automation = table::borrow_mut(user_tracker, uid);
            if (automation.i > 0 && automation.expiry >= timestamp::now_seconds()){
                automation.i = automation.i - 1;
                return true
            } else {
                return false
            }
        }
    }
}
