module dev::QiaraMessagesV1 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;

    const ADMIN: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_SENDER_DOESNT_EXISTS: u64 = 2;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    struct MessagesDatabase has key {
        messages: table::Table<address, vector<vector<u8>>>,
    }

    struct SenderList has key {
        list: vector<address>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);

        if (!exists<MessagesDatabase>(ADMIN)) {
            move_to(
                admin,
                MessagesDatabase { messages: table::new<address, vector<vector<u8>>>() }
            );
        };

        if (!exists<SenderList>(ADMIN)) {
            move_to(
                admin,
                SenderList { list: vector::empty<address>() }
            );
        };
    }

    // ----------------------------------------------------------------
    // Entry: send a message
    // ----------------------------------------------------------------
    public entry fun send_message(user: &signer, message: vector<u8>) acquires MessagesDatabase, SenderList {
        let addr = signer::address_of(user);
        let sender_list = borrow_global_mut<SenderList>(ADMIN);
        let messages_db = borrow_global_mut<MessagesDatabase>(ADMIN);

        // Ensure sender has an entry in the table
        if (!table::contains(&messages_db.messages, addr)) {
            table::add(&mut messages_db.messages, addr, vector::empty<vector<u8>>());
        };

        // Add sender to sender list if not already present
        if (!vector::contains(&sender_list.list, &addr)) {
            vector::push_back(&mut sender_list.list, addr);
        };

        // Append the new message
        let messages_ref = table::borrow_mut(&mut messages_db.messages, addr);
        vector::push_back(messages_ref, message);
    }

    // ----------------------------------------------------------------
    // Entry: remove messages from a sender
    // ----------------------------------------------------------------
    public entry fun remove_old_messages(user: &signer, sender: address) acquires MessagesDatabase, SenderList {
        assert!(signer::address_of(user) == ADMIN, ERROR_NOT_ADMIN);
        let sender_list = borrow_global_mut<SenderList>(ADMIN);
        let messages_db = borrow_global_mut<MessagesDatabase>(ADMIN);

        // Ensure sender exists in the list
        if (!vector::contains(&sender_list.list, &sender)) {
            abort(ERROR_SENDER_DOESNT_EXISTS);
        };

        // Delete senders messages
        table::remove(&mut messages_db.messages, sender);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------
    #[view]
    public fun view_messages(sender: address): vector<vector<u8>> acquires MessagesDatabase {
        let messages_db = borrow_global<MessagesDatabase>(ADMIN);
        if (table::contains(&messages_db.messages, sender)) {
            // borrow returns &vector<vector<u8>> - copy it to return an owned vector
            *table::borrow(&messages_db.messages, sender)
        } else {
            vector::empty<vector<u8>>()
        }
    }

    #[view]
    public fun view_messages_string(sender: address): vector<String> acquires MessagesDatabase {
        let messages_db = borrow_global<MessagesDatabase>(ADMIN);
        let vect = vector::empty<String>();

        if (table::contains(&messages_db.messages, sender)) {
            let messages = table::borrow(&messages_db.messages, sender);
            let len = vector::length(messages);
            let i = 0;
            while (i < len) {
                let message = vector::borrow(messages, i);
                let string_message = string::utf8(*message);
                vector::push_back(&mut vect, string_message);
                i = i + 1;
            };
            vect
        } else {
            vector::empty<String>()
        }
    }


}
