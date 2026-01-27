module dev::zk_balances_testv1{
    use std::vector;
    use std::signer;
    use supra_framework::event;
    use std::timestamp;
    use std::string::{Self as String, String, utf8};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};
    // --- CUSTOM SERIALIZATION CONSTANTS ---
    // User requirement: u256 from ZK should be treated as Little Endian bytes
    

    struct AddressCounter has key {
        counter: u64,
    }

    // if address is in database
    struct AddressDatabase has key {
        table: Table<address, bool>,
    }

    // database with pagination
    // Page -> address -> chain -> token -> balance
    struct Database has key {
        page: Table<u64, Map<address, Map<String, Map<String, u256>>>>,
    }

// === EVENTS === //

    const ERROR_NOT_ADMIN: u64 = 1;
    const EOutOfPaginationBounds: u64 = 2;

    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, AddressCounter {counter: 0});
        move_to(admin, AddressDatabase {table: table::new<address, bool>()});
        move_to(admin, Database {page: table::new<u64, Map<address, Map<String, Map<String, u256>>>>()});
    }

public entry fun test_register_fake_balance(
    addr: address,
    token: String,
    chain: String, 
    amount: u256
) acquires AddressCounter, AddressDatabase, Database {
    let addressDatabase_ref = borrow_global_mut<AddressDatabase>(@dev);
    let addressCounter_ref = borrow_global_mut<AddressCounter>(@dev);
    let database_ref = borrow_global_mut<Database>(@dev);

    // 1. Determine or Retrieve Page Number
    let page_number: u64;
    if (!table::contains(&addressDatabase_ref.table, addr)) {
        // New Address Logic
        page_number = addressCounter_ref.counter / 100;
        table::add(&mut addressDatabase_ref.table, addr, true); // Store the page!

        if (!table::contains(&database_ref.page, page_number)) {
            table::add(&mut database_ref.page, page_number, map::new<address, Map<String, Map<String, u256>>>());
        };
        
        let page_table = table::borrow_mut(&mut database_ref.page, page_number);
        map::add(page_table, addr, map::new<String, Map<String, u256>>());
        addressCounter_ref.counter = addressCounter_ref.counter + 1;
    } ;
        page_number = addressCounter_ref.counter / 100;
    // 2. Navigate the nested structure safely
    let page_table = table::borrow_mut(&mut database_ref.page, page_number);
    let address_map = map::borrow_mut(page_table, &addr); // This is Map<String, Map<String, u256>> (Chains)

    // Handle Chain Level
    if (!map::contains_key(address_map, &chain)) {
        map::add(address_map, chain, map::new<String, u256>());
    };
    let chain_map = map::borrow_mut(address_map, &chain); // This is Map<String, u256> (Tokens)

    // Handle Token Level
    if (!map::contains_key(chain_map, &token)) {
        map::add(chain_map, token, amount);
    } else {
        let token_balance = map::borrow_mut(chain_map, &token);
        *token_balance = *token_balance + amount;
    };
}



    #[view]
    public fun get_fake_balance_page(page: u64) : Map<address, Map<String, Map<String, u256>>> acquires Database, AddressCounter {
        let database_ref = borrow_global<Database>(@dev);
        let counter_ref = borrow_global<AddressCounter>(@dev);
        //abort counter_ref.counter;
        let max_page = counter_ref.counter / 100;
        if (page > max_page) {
            abort EOutOfPaginationBounds
        };
        if (!table::contains(&database_ref.page, page)) {
            abort EOutOfPaginationBounds
        };
         return *table::borrow(&database_ref.page, page)
    } 


    #[view]
    public fun get_fake_balance_page_by_chain(page: u64, chain: String) : Map<address, Map<String, u256>> acquires Database, AddressCounter {
        let database_ref = borrow_global<Database>(@dev);
        let counter_ref = borrow_global<AddressCounter>(@dev);
        //abort counter_ref.counter;
        let max_page = counter_ref.counter / 100;
        if (page > max_page) {
            abort EOutOfPaginationBounds
        };
        if (!table::contains(&database_ref.page, page)) {
            abort EOutOfPaginationBounds
        };

         let page_table = *table::borrow(&database_ref.page, page);
         let keys = map::keys(&page_table);
         let len = vector::length(&keys);

            let return_map = map::new<address, Map<String, u256>>();

         while(len > 0) {
            let addr = *vector::borrow(&keys, len-1);
            let chain_table = *map::borrow(&page_table, &addr);
            if (map::contains_key(&chain_table, &chain)) {
                let token_table = map::borrow(&chain_table, &chain);
                map::add(&mut return_map, addr, *token_table);
            };
            len = len - 1;
         };
            return return_map
    } 
    
}