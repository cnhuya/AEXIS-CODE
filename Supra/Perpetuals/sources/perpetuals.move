module dev::QiaraPerpsV12{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;

    use dev::QiaraMarginV14::{Self as Margin, Access as MarginAccess};
    use dev::QiaraVerifiedTokensV5::{Self as VerifiedTokens};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;

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

/// === STRUCTS ===
    struct BTC has store, key{}

    struct Permissions has key {
        margin: MarginAccess
    }

    struct Position<T> has copy, drop, store, key {
        size: u64,
        entry_price: u128,
        is_long: bool,
        leverage: u64,
    }

    struct ViewPosition<T> has copy, drop, store, key {
        used_margin: u256,
        usd_size: u256,
        size: u64,
        entry_price: u128,
        is_long: bool,
        leverage: u64,
        pnl: u256,
        is_profit: bool,
        denom: u64,
    }

    struct UserBook<T> has key, store {
        book: table::Table<address, Position<T>>,
    }

/// === INIT ===
    fun init_module(admin: &signer){
        create_market<BTC>(admin);
    }

/// === ENTRY FUNCTIONS ===
    public entry fun create_market<T: store>(admin: &signer){
        if (!exists<UserBook<T>>(signer::address_of(admin))) {
            move_to(admin, UserBook<T> { book: table::new<address, Position<T>>()});
        };
    }

    fun find_position<T: store>(user: address, user_book: &mut UserBook<T>): &mut Position<T> {

        if (!table::contains(&user_book.book, user)) {
            table::add(&mut user_book.book, user, Position<T> { size:0, entry_price:0, is_long:false, leverage:0});
        };

        table::borrow_mut(&mut user_book.book, user)
    }

    public entry fun long<T: store, A,B>(address: address, size:u64, leverage:u64) acquires UserBook, Permissions{
        let position = find_position<T>(address,  borrow_global_mut<UserBook<T>>(@dev));
        let price = VerifiedTokens::get_coin_metadata_price(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));
        if(price == 0){
            abort 100;
        };
        let (size_diff_usd, is_profit) = calculate_position(position, size, leverage, false, price);
        handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
    }

    public entry fun short<T: store, A,B>(address: address, size:u64, leverage:u64) acquires UserBook, Permissions{
        let position = find_position<T>(address, borrow_global_mut<UserBook<T>>(@dev));
        let price = VerifiedTokens::get_coin_metadata_price(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));
        let (size_diff_usd, is_profit) = calculate_position(position, size, leverage, false, price);
        handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
    }

/// === HELPER FUNCTIONS ===
    fun handle_pnl<T: store,A,B>(pnl: u256, is_profit: bool, user: address) acquires Permissions{
        if(pnl == 0) { return; }; // no PnL to handle
        if(is_profit){
            Margin::add_rewards<T>(user, (getValueByCoin<T,A>(pnl) as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        } else {
            Margin::add_interest<T>(user,  (getValueByCoin<T,B>(pnl) as u64), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        }
    }

   // converts usd back to coin value
    fun getValueByCoin<A,B>(amount_in: u256): u256{

        // Step 3: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<A>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<B>());

        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u128) * price_in) / price_out;

        return (amount_out as u256) 
    }

    fun calculate_position<T>(position: &mut Position<T>,added_size: u64,leverage: u64,is_long: bool,oracle_price: u128): (u256, bool) {
        // Case 1: No existing position - open new
        if (position.size == 0) {
            position.size = added_size;
            position.leverage = leverage;
            position.is_long = is_long;
            position.entry_price = oracle_price;
            return (0, true); // no PnL
        };

        let curr_size: u256 = (position.size as u256);
        let curr_lev: u256 = (position.leverage as u256);
        let curr_price: u256 = (position.entry_price as u256);
        let add_size: u256 = (added_size as u256);
        let lev: u256 = (leverage as u256);
        let price: u256 = (oracle_price as u256);

        let weighted_curr_lev = curr_size * curr_lev;
        let weighted_curr_price = curr_size * curr_price;

        // Case 2: Same direction - add exposure
        if (position.is_long == is_long) {
            let weighted_new_lev = add_size * lev;
            let weighted_new_price = add_size * price;

            let new_size = curr_size + add_size;
            let new_leverage = (weighted_curr_lev + weighted_new_lev) / new_size;
            let new_price = (weighted_curr_price + weighted_new_price) / new_size;

            position.size = (new_size as u64);
            position.leverage = (new_leverage as u64);
            position.entry_price = (new_price as u128);

            return (0, true) // no realized PnL
        };

        // Case 3: Opposite direction - reduce or flip
        if (add_size >= curr_size) {
            // Closing entire position (and maybe flipping)
            let closed_size = curr_size;
            let (pnl, is_profit) = if (position.is_long) {
                if (price >= curr_price) {
                    ((price - curr_price) * closed_size, true)
                } else {
                    ((curr_price - price) * closed_size, false)
                }
            } else {
                if (curr_price >= price) {
                    ((curr_price - price) * closed_size, true)
                } else {
                    ((price - curr_price) * closed_size, false)
                }
            };

            // Now flip into new side
            position.size = ((add_size - curr_size) as u64);
            position.leverage = leverage;
            position.is_long = is_long;
            position.entry_price = oracle_price;

            return (pnl, is_profit)
        } else {
            // Partial close
            let closed_size = add_size;
            let (pnl, is_profit) = if (position.is_long) {
                if (price >= curr_price) {
                    ((price - curr_price) * closed_size, true)
                } else {
                    ((curr_price - price) * closed_size, false)
                }
            } else {
                if (curr_price >= price) {
                    ((curr_price - price) * closed_size, true)
                } else {
                    ((price - curr_price) * closed_size, false)
                }
            };

            position.size = ((curr_size - add_size) as u64);
            // leverage & entry_price unchanged

            return (pnl, is_profit)
        }
    }


    fun estimate_pnl<T>(position: &Position<T>, oracle_price: u256): (u256, bool) {
        let size = (position.size as u256);
        let entry_price = (position.entry_price as u256);

        // notional values
        let usd_size = size * entry_price;
        let now_usd_size = size * oracle_price;

        if (position.is_long) {
            if (oracle_price >= entry_price) {
                // long and price went up -> profit
                (now_usd_size - usd_size, true)
            } else {
                // long and price went down -> loss
                (usd_size - now_usd_size, false)
            }
        } else {
            if (oracle_price <= entry_price) {
                // short and price went down -> profit
                (usd_size - now_usd_size, true)
            } else {
                // short and price went up -> loss
                (now_usd_size - usd_size, false)
            }
        }
    }

/// === VIEW FUNCTIONS ===
    #[view]
    public fun get_position<T: store + drop>(user: address): Position<T> acquires UserBook {
        let user_book = borrow_global<UserBook<T>>(@dev);

        if (!table::contains(&user_book.book, user)) {
            return Position<T> { size:0, entry_price:0, is_long:false, leverage:0};
        };

        let position = table::borrow(&user_book.book, user);
        Position<T> { size: position.size , entry_price: position.entry_price, is_long:position.is_long, leverage:position.leverage}
    }

    #[view]
    public fun get_view_position<T: store + drop>(user: address): ViewPosition<T> acquires UserBook {
        let user_book = borrow_global_mut<UserBook<T>>(@dev);

        if (!table::contains(&user_book.book, user)) {
            return ViewPosition<T> { used_margin: 0, usd_size: 0, size:0, entry_price:0, is_long:false, leverage:0, pnl: 0, is_profit: false, denom: 0};
        };
        let position = table::borrow_mut(&mut user_book.book, user);

        let price = VerifiedTokens::get_coin_metadata_price(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));
        let denom = VerifiedTokens::get_coin_metadata_denom(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));
        let (pnl, is_profit) = estimate_pnl<T>(position, (price as u256));

        ViewPosition<T> {used_margin: ((position.size as u256)*(position.entry_price as u256) / (position.leverage as u256)), usd_size: (position.size as u256)*(position.entry_price as u256),  size: position.size , entry_price: position.entry_price, is_long:position.is_long, leverage:position.leverage, pnl: pnl, is_profit: is_profit, denom: (denom as u64)}
    }

}
