module dev::QiaraInterestV1{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;

    use dev::QiaraMarginV1::{Self as Margin, Access as MarginAccess};
    use dev::QiaraVerifiedTokensV1::{Self as VerifiedTokens};

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(s: &signer, access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key {
        margin: MarginAccess
    }

/// === STRUCTS ===
  
    struct Credit has drop, store, key {}
    struct USD has drop, store, key {}
  
    struct OrderBook has key {
        book: table::Table<u8, vector<Address>>,
        current_page: u32,
    }

/// === FUNCTIONS ===
    fun init_module(admin: &signer){
        if (!exists<OrderBook>(signer::address_of(admin))) {
            move_to(admin, OrderBook { book: table::new<u8, vector<Address>(), current_page:0 });
        };
    }

    public fun register_adress_to_order_book(address: address, cap: Permission) acquires OrderBook{
        let order_book = borrow_global<OrderBook>(@dev);
        let current_page = order_book.current_page;

        let page = table::borrow_mut(&mut order_book.book, current_page);
        if(vector::length(&page) < 100){
            vector::push_back(&page, address);
        } else{
            current_page = current_page + 1;
            table::add(&mut order_book.book, current_page, vector[address]);
        }
    }

    public fun check_order_book() acquires OrderBook{
        let order_book = borrow_global<OrderBook>(@dev);
        let current_page = order_book.current_page;

        let page = table::borrow_mut(&mut order_book.book, current_page);
        let len = vector::length(&page);
        if(len>0){
            let adress = vector::borrow(&page, len-1);
            pay_interest(address);
            len=len-1;
        }
    }

    fun pay_interest(addr: address){
        let utilization = Margin::get_utilization_ratio(addr);
        let last_updated = Margin::get_last_updated<USD, CREDIT>(addr);
        if((!timestamp::now_seconds() / 3600) - last_updated = 0){
            Margin::update_time<USD, CREDIT>;
           let coin_metadata = VerifiedTokens::get_coin_metadata_by_res();
        }

        let page = table::borrow_mut(&mut order_book.book, current_page);
        let len = vector::length(&page);
        if(len>0){
            let adress = vector::borrow(&page, len-1);
            // claim rewards/compound interest...
            len=len-1;
        }
    }


}
