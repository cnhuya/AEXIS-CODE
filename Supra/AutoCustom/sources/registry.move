module dev::QiaraAutomationV6 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use std::timestamp;
    use std::table::{Self, Table};
    use std::signer;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use supra_framework::event;

    use dev::QiaraTokensSharedV51::{Self as TokensShared};


// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

// === ERRORS === //

    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_UNKNOWN: u64 = 1;
    const ERROR_ADDRESS_NOT_INIT: u64 = 2;
    const ERROR_FUNCTION_ID_NOT_INIT: u64 = 3;
    const ERROR_AUTOMATED_TX_NOT_FOUND_UNDER_COUNTER: u64 = 4;
    const ERROR_ARG_LENGHT_DOESNT_MATCH: u64 = 5;
    const ERROR_UNSPECIFIED_FUNCTION_ID: u64 = 6;
    const ERROR_TYPE_ARGS_NOT_CORRECT_LENGTH: u64 = 7;
    const ERROR_ARGS_NOT_CORRECT_LENGTH: u64 = 8;

    const ERROR_TYPE_ARG_1_INVALID: u64 = 10;
    const ERROR_TYPE_ARG_2_INVALID: u64 = 11;
    const ERROR_TYPE_ARG_3_INVALID: u64 = 12;

/// === INIT ===
    fun init_module(admin: &signer) {
        if (!exists<AutomatedTransactionsTracker>(@dev)) {
            move_to(admin, AutomatedTransactionsTracker { 
                tracker: table::new<vector<u8>, Table<u8, Map<u128, Data>>>() 
            });
        };
    }

/// === STRUCTS ===
/// Address -> Function ID -> UID -> arguments for the function for validator

    struct Data has key, copy, drop, store {
        type_args: vector<String>,
        args: vector<vector<u8>>
    }

    struct AutomatedTransactionsTracker has key {
        tracker: Table<vector<u8>, Table<u8, Map<u128, Data>>>
    }

    struct AutomatedTransactionsCounter has key {
        counter: Table<vector<u8>, u128>
    }

/// === EVENTS ===
    #[event]
    struct AutomationRegisterEvent has copy, drop, store {
        address: vector<u8>,
        function_id: u8,
        uid: u128,
        type_args: vector<String>,
        args: vector<vector<u8>>,
        time: u64
    }
    



/// === FUNCTIONS ===
    // Native Interface
        public entry fun register_automation(signer: &signer, owned_storage: vector<u8>, function_id: u8, type_args: vector<String>, args: vector<vector<u8>>) acquires AutomatedTransactionsTracker, AutomatedTransactionsCounter {
            TokensShared::assert_is_sub_owner(owned_storage, bcs::to_bytes(&signer::address_of(signer)));
            
            assert_correct_arguments(function_id, type_args, args);
            
            let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
            let tracker_counter = borrow_global_mut<AutomatedTransactionsCounter>(@dev);
            
            // Initialize user's tracker table if not exists
            if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
                table::add(&mut tracker_bookshelf.tracker, owned_storage, table::new<u8, Map<u128, Data>>());
            };

            if (!table::contains(&tracker_counter.counter, owned_storage)) {
                table::add(&mut tracker_counter.counter, owned_storage, 0);
            };
            
            let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, owned_storage);
            
            // Initialize function_id table if not exists
            if (!table::contains(user_tracker, function_id)) {
                table::add(user_tracker, function_id, map::new<u128, Data>());
            };
            
            let function_table = table::borrow_mut(user_tracker, function_id);
            let counter = table::borrow_mut(&mut tracker_counter.counter, owned_storage);
            // Update or create the UID entry
            if (map::contains_key(function_table, &*counter)) {
                // Replace existing args
                let data = map::borrow_mut(function_table, counter);
                data.args = args;
            } else {
                // Create new entry
                map::add(function_table, *counter, Data {type_args: type_args, args: args});

                event::emit(AutomationRegisterEvent {
                    address: owned_storage,
                    function_id: function_id,
                    uid: *counter,
                    type_args: type_args,
                    args: args,
                    time: timestamp::now_seconds()
                })
            };

            // Increment counter
            *counter = *counter + 1;
        }

        public entry fun update_automation(signer: &signer, owned_storage: vector<u8>, function_id: u8, counter: u128, type_args: vector<String>, args: vector<vector<u8>>) acquires AutomatedTransactionsTracker {
            TokensShared::assert_is_sub_owner(owned_storage, bcs::to_bytes(&signer::address_of(signer)));   
            
            let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
            
            // Initialize user's tracker table if not exists
            if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
                abort ERROR_ADDRESS_NOT_INIT
            };
            
            let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, owned_storage);
            
            // Initialize function_id table if not exists
            if (!table::contains(user_tracker, function_id)) {
                abort ERROR_FUNCTION_ID_NOT_INIT
            };
            
            let function_table = table::borrow_mut(user_tracker, function_id);
            // Update or create the UID entry
            if (map::contains_key(function_table, &counter)) {
                // Replace existing args
                let data = map::borrow_mut(function_table, &counter);
                data.args = args;
            } else {
                abort ERROR_AUTOMATED_TX_NOT_FOUND_UNDER_COUNTER
            };

        }
    // Permissionless Interface
        public fun p_register_automation(validator: &signer, owned_storage: vector<u8>, sub_owner: vector<u8>, function_id: u8, type_args: vector<String>, args: vector<vector<u8>>, perm: Permission) acquires AutomatedTransactionsTracker, AutomatedTransactionsCounter {
            TokensShared::assert_is_sub_owner(owned_storage, sub_owner);   
            
            assert_correct_arguments(function_id, type_args, args);
            
            let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
            let tracker_counter = borrow_global_mut<AutomatedTransactionsCounter>(@dev);
            
            // Initialize user's tracker table if not exists
            if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
                table::add(&mut tracker_bookshelf.tracker, owned_storage, table::new<u8, Map<u128, Data>>());
            };

            if (!table::contains(&tracker_counter.counter, owned_storage)) {
                table::add(&mut tracker_counter.counter, owned_storage, 0);
            };
            
            let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, owned_storage);
            
            // Initialize function_id table if not exists
            if (!table::contains(user_tracker, function_id)) {
                table::add(user_tracker, function_id, map::new<u128, Data>());
            };
            
            let function_table = table::borrow_mut(user_tracker, function_id);
            let counter = table::borrow_mut(&mut tracker_counter.counter, owned_storage);
            // Update or create the UID entry
            if (map::contains_key(function_table, &*counter)) {
                // Replace existing args
                let data = map::borrow_mut(function_table, counter);
                data.args = args;
            } else {
                // Create new entry
                map::add(function_table, *counter, Data {type_args: type_args, args: args});

                event::emit(AutomationRegisterEvent {
                    address: owned_storage,
                    function_id: function_id,
                    uid: *counter,
                    type_args: type_args,
                    args: args,
                    time: timestamp::now_seconds()
                })
            };

            // Increment counter
            *counter = *counter + 1;
        }

        public fun p_update_automation(validator: &signer, owned_storage: vector<u8>, sub_owner: vector<u8>, function_id: u8, counter: u128, type_args: vector<String>, args: vector<vector<u8>>, perm: Permission) acquires AutomatedTransactionsTracker {
            TokensShared::assert_is_sub_owner(owned_storage, sub_owner);              
            
            assert_correct_arguments(function_id, type_args, args);
            
            let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);
            
            // Initialize user's tracker table if not exists
            if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
                abort ERROR_ADDRESS_NOT_INIT
            };
            
            let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, owned_storage);
            
            // Initialize function_id table if not exists
            if (!table::contains(user_tracker, function_id)) {
                abort ERROR_FUNCTION_ID_NOT_INIT
            };
            
            let function_table = table::borrow_mut(user_tracker, function_id);
            // Update or create the UID entry
            if (map::contains_key(function_table, &counter)) {
                // Replace existing args
                let data = map::borrow_mut(function_table, &counter);
                data.args = args;
            } else {
                abort ERROR_AUTOMATED_TX_NOT_FOUND_UNDER_COUNTER
            };

        }

    public fun execute(validator:signer, owned_storage: vector<u8>, function_id: u8, counter: u128, perm: Permission) acquires AutomatedTransactionsTracker {
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);

        if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
            return
        };
        
        let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, owned_storage);
        
        if (!table::contains(user_tracker, function_id)) {
            return
        };
        
        let function_table = table::borrow_mut(user_tracker, function_id);
        
        if (map::contains_key(function_table, &counter)) {
            map::remove(function_table, &counter);
        }
    }

    fun assert_correct_arguments(function_id: u8, type_args: vector<String>, args: vector<vector<u8>>) {
        assert!(vector::length(&type_args) == vector::length(&args), ERROR_ARG_LENGHT_DOESNT_MATCH);

         if (function_id == 1) { // swap trade
             assert!(vector::length(&type_args) == 2, ERROR_TYPE_ARGS_NOT_CORRECT_LENGTH);
             assert!(vector::length(&args) == 2, ERROR_ARGS_NOT_CORRECT_LENGTH);

             assert!(*vector::borrow(&type_args, 0) == utf8(b"token"), ERROR_TYPE_ARG_1_INVALID);
             assert!(*vector::borrow(&type_args, 1) == utf8(b"price"), ERROR_TYPE_ARG_2_INVALID);
         }
            else if (function_id == 2) { // perps trade
                assert!(vector::length(&type_args) == 3, ERROR_TYPE_ARGS_NOT_CORRECT_LENGTH);
                assert!(vector::length(&args) == 3, ERROR_ARGS_NOT_CORRECT_LENGTH);

                assert!(*vector::borrow(&type_args, 0) == utf8(b"token"), ERROR_TYPE_ARG_1_INVALID);
                assert!(*vector::borrow(&type_args, 1) == utf8(b"price"), ERROR_TYPE_ARG_2_INVALID);
                assert!(*vector::borrow(&type_args, 2) == utf8(b"leverage"), ERROR_TYPE_ARG_3_INVALID);
            } else {
                abort ERROR_UNSPECIFIED_FUNCTION_ID;
            }
    }

    #[view]
    public fun uid_exists(owned_storage: vector<u8>, function_id: u8, uid: u128): Data acquires AutomatedTransactionsTracker{
        let tracker_bookshelf = borrow_global_mut<AutomatedTransactionsTracker>(@dev);        
        
        if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
            abort ERROR_ADDRESS_NOT_INIT
        };

        let user_tracker = table::borrow_mut(&mut tracker_bookshelf.tracker, owned_storage);

        if (!table::contains(user_tracker, function_id)) {
           abort ERROR_FUNCTION_ID_NOT_INIT
        };
        
        let function_table = table::borrow_mut(user_tracker, function_id);

        if (map::contains_key(function_table, &uid)) {
            return *map::borrow(function_table, &uid);
        };

        abort ERROR_UNKNOWN   
    }

    #[view]
    public fun get_all_uids(owned_storage: vector<u8>, function_id: u8): vector<u128> acquires AutomatedTransactionsTracker {
        let tracker_bookshelf = borrow_global<AutomatedTransactionsTracker>(@dev);        
        
        if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
            return vector::empty<u128>()
        };

        let user_tracker = table::borrow(&tracker_bookshelf.tracker, owned_storage);

        if (!table::contains(user_tracker, function_id)) {
            return vector::empty<u128>()
        };
        
        let function_automations = table::borrow(user_tracker, function_id);
        map::keys(function_automations)
    }

    #[view]
    public fun get_all_values(owned_storage: vector<u8>, function_id: u8): vector<Data> 
    acquires AutomatedTransactionsTracker {
        let tracker_bookshelf = borrow_global<AutomatedTransactionsTracker>(@dev);        
        
        if (!table::contains(&tracker_bookshelf.tracker, owned_storage)) {
            abort ERROR_ADDRESS_NOT_INIT
        };

        let user_tracker = table::borrow(&tracker_bookshelf.tracker, owned_storage);

        if (!table::contains(user_tracker, function_id)) {
             abort ERROR_FUNCTION_ID_NOT_INIT
        };
        
        let function_automations = table::borrow(user_tracker, function_id);
        map::values(function_automations)
    }

}
