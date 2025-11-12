module dev::QiaraPerpsV31{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use std::timestamp;
    use supra_framework::event;
    use dev::QiaraMarginV45::{Self as Margin, Access as MarginAccess};
    use dev::QiaraVerifiedTokensV42::{Self as VerifiedTokens};
    use dev::QiaraFeatureTypesV11::{Self as FeatureTypes, Perpetuals};
    use dev::QiaraCoinTypesV11::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui};
    use dev::QiaraMathV9::{Self as QiaraMath};
// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_MARKET_ALREADY_EXISTS: u64 = 2;
    const ERROR_LEVERAGE_TOO_LOW: u64 = 3;

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

    struct Permissions has key {
        margin: MarginAccess
    }

    struct Asset has store, key{
        asset: String,
        shorts: u256,
        longs: u256,
        leverage: u64
    }
    
    struct ViewAsset has store, key{
        asset: String,
        shorts: u256,
        longs: u256,
        oi: u256,
        leverage: u64,
        liquidity: u256,
        utilization: u64,
        price: u256,
        denom: u256,
    }

    struct Position<T> has copy, drop, store, key {
        size: u256,
        entry_price: u256,
        is_long: bool,
        leverage: u64,
    }

    struct ViewPosition has copy, drop, store, key {
        asset: String,
        used_margin: u256,
        usd_size: u256,
        size: u256,
        entry_price: u256,
        price: u256,
        is_long: bool,
        leverage: u64,
        pnl: u256,
        is_profit: bool,
        denom: u256,
        profit_fee: u64,
    }

    struct AssetBook has key, store {
        book: table::Table<String, Asset>,
    }

    struct UserBook<T> has key, store {
        book: table::Table<address, Position<T>>,
    }

    struct Markets has key, store{
        list: vector<String>
    }

// === EVENTS === //
    #[event]
    struct Trade has copy, drop, store {
        trader: address,
        is_long: bool,
        size: u256,
        leverage:u64,
        used_margin: u256,
        asset: String,
        type: String,
        entry_price: u256,
        fee: u256,
        time: u64
    }

    #[event]
    struct TradeReg has copy, drop, store {
        trader: address,
        is_long: bool,
        size: u256,
        leverage:u64,
        used_margin: u256,
        asset: String,
        type: String,
        entry_price: u256,
        desired_price: u256,
        fee: u256,
        time: u64,
        success: bool,
    }

/// === INIT ===
    fun init_module(admin: &signer) acquires Markets, AssetBook{

        if (!exists<Markets>(@dev)) {
            move_to(admin, Markets { list: vector::empty<String>()});
        };

        if (!exists<AssetBook>(@dev)) {
            move_to(admin, AssetBook { book: table::new<String, Asset>()});
        };

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { margin: Margin::give_access(admin),});
        };


        create_market<SuiBitcoin>(admin);
        create_market<SuiEthereum>(admin);
        create_market<SuiSui>(admin);
    }


/// === ENTRY FUNCTIONS ===
    public entry fun create_market<T: store>(admin: &signer) acquires Markets, AssetBook{
        if (!exists<UserBook<T>>(@dev)) {
            move_to(admin, UserBook<T> { book: table::new<address, Position<T>>()});
        };

        let asset_book = borrow_global_mut<AssetBook>(@dev);

        if (!table::contains(&asset_book.book, type_info::type_name<T>())) {
            table::add(&mut asset_book.book, type_info::type_name<T>(), Asset { 
                asset:  type_info::type_name<T>(),
                shorts: 0,
                longs: 0,
                leverage: 0,
            });
        };

        let markets = borrow_global_mut<Markets>(@dev);
        assert!(!vector::contains(&markets.list, &type_info::type_name<T>()),ERROR_MARKET_ALREADY_EXISTS);
        vector::push_back(&mut markets.list, type_info::type_name<T>());
    }

    fun find_position<T: store>(user: address, user_book: &mut UserBook<T>): &mut Position<T> {
        if (!table::contains(&user_book.book, user)) {
            table::add(&mut user_book.book, user, Position<T> { 
                size: 0, 
                entry_price: 0, 
                is_long: false, 
                leverage: 0 
            });
        };
        table::borrow_mut(&mut user_book.book, user)
    }

    fun find_asset<T: store>(asset_book: &mut AssetBook): &mut Asset {
        table::borrow_mut(&mut asset_book.book, type_info::type_name<T>())
    }

    fun ttta(a: u64){
        abort(a);
    }


    public entry fun trade<T: store, A,B>(address: address, size:u256, leverage: u64, limit: u256, side: String, type: String) acquires UserBook, AssetBook, Permissions {
        let position = find_position<T>(address,  borrow_global_mut<UserBook<T>>(@dev));
        let asset_book = borrow_global_mut<AssetBook>(@dev);
        let price = VerifiedTokens::get_coin_metadata_price(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));
        assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);
        let is_long: bool = false;

        if(type == utf8(b"market")){
            if(side == utf8(b"long")){
                is_long = true;
            } else if(side == utf8(b"short")){
                is_long = false;
            };
            let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size, leverage, is_long, (price as u128), address);
            handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
        } else if (type == utf8(b"limit")) {
            if ((side == utf8(b"long")) && (limit >= price)) {
                let (size_diff_usd, is_profit) = calculate_position(asset_book, position, size, leverage, true, (price as u128), address);
                handle_pnl<T, A, B>(size_diff_usd, is_profit, address);
            } else if ((side == utf8(b"short")) && (limit <= price)) {
                let (size_diff_usd, is_profit) = calculate_position(asset_book, position, size, leverage, false, (price as u128), address);
                handle_pnl<T, A, B>(size_diff_usd, is_profit, address);
            };
        } else if(type == utf8(b"other")){
            if(side == utf8(b"flip") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size*2, leverage, false, (price as u128), address);
                handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
            } else if(side == utf8(b"flip") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size*2, leverage, true, (price as u128), address);
                handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
            } else if(side == utf8(b"close") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size, leverage, true, (price as u128), address);
                handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
            } else if(side == utf8(b"close") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size, leverage, false, (price as u128), address);
                handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
            } else if(side == utf8(b"double") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size, leverage, true, (price as u128), address);
                handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
            } else if(side == utf8(b"double") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(asset_book,position, size, leverage, false, (price as u128), address);
                handle_pnl<T,A,B>(size_diff_usd, is_profit, address);
            };
        };
    }



/// === HELPER FUNCTIONS ===
fun handle_pnl<T: store, A, B>(pnl: u256, is_profit: bool, user: address) acquires Permissions {
    if (pnl == 0) { 
        return; 
    };
    
    if (is_profit) {
        let reward = getValueByCoin<T, A>(pnl);
        Margin::add_rewards<T, Perpetuals>(user, reward, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
       // ttta(6);
    } else {
      //  ttta(7);
        let interest = getValueByCoin<T, B>(pnl);
       // ttta(8);
        
        // Debug: Check if permissions exist
        let permissions = borrow_global<Permissions>(@dev);
       // ttta(888); // Should reach here
        
        // Debug: Check the margin permission
        let cap = Margin::give_permission(&permissions.margin);
       // ttta(889); // Should reach here
        
        // Try the call
        Margin::add_interest<T, Perpetuals>(user, interest, cap);
        //ttta(9);
    };
    //ttta(10);
}

   // converts usd back to coin value
    fun getValueByCoin<T,B>(amount_in: u256): u256{

        // Step 3: calculate output amount in Y (simple price * ratio example)
        let metadata_in = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());
        let metadata_out = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<B>());
        let price_in =  VerifiedTokens::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  VerifiedTokens::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u256) * price_in) / price_out;
        //ttta(((amount_out/10000000) as u64));
        return (amount_out) 
    }

    fun calculate_position<T: store>(asset_book: &mut AssetBook,position: &mut Position<T>,added_size: u256,leverage: u64,is_long: bool,oracle_price: u128, address: address): (u256, bool){
        let asset = find_asset<T>(asset_book);

        let curr_size: u256 = (position.size as u256);
        let add_size: u256 = (added_size as u256);
        let lev: u256 = (leverage as u256);
        let price: u256 = (oracle_price as u256);
        // Case 1: No existing position - open new
        if (position.size == 0) {
            position.size = added_size;
            position.leverage = leverage;
            position.is_long = is_long;
            position.entry_price = price;
            
            // Update asset tracking
            update_asset_leverage(asset, add_size, lev, is_long, true);

            event::emit(Trade {
                trader: address,
                is_long: is_long,
                size: added_size,
                leverage: leverage,
                used_margin: (added_size/lev)*100,
                asset: type_info::type_name<T>(),
                type: utf8(b"Open Position"),
                entry_price: price,
                fee: 0,
                time: timestamp::now_seconds(),
            });

            return (0, true);
        };

        let curr_lev: u256 = (position.leverage as u256);
        let curr_price: u256 = (position.entry_price as u256);
        let weighted_curr_lev = curr_size * curr_lev;
        let weighted_curr_price = curr_size * curr_price;

        // Case 2: Same direction - add exposure
        if (position.is_long == is_long) {
            let weighted_new_lev = add_size * lev;
            let weighted_new_price = add_size * price;

            let new_size = curr_size + add_size;
            let new_leverage = (weighted_curr_lev + weighted_new_lev) / new_size;
            let new_price = (weighted_curr_price + weighted_new_price) / new_size;

            position.size = new_size;
            position.leverage = (new_leverage as u64);
            position.entry_price = (new_price as u256);

            // Update asset tracking (add to existing)
            update_asset_leverage(asset, add_size, lev, is_long, true);

            event::emit(Trade {
                trader: address,
                is_long: is_long,
                size: added_size,
                leverage: leverage,
                used_margin: (added_size/lev)*100,
                asset: type_info::type_name<T>(),
                type: utf8(b"Add Size"),
                entry_price: price,
                fee: 0,
                time: timestamp::now_seconds(),
            });

            return (0, true) // no realized PnL
        };

        // Case 3: Opposite direction - reduce or flip
        if (add_size >= curr_size) {
            // Closing entire position (and maybe flipping)
            let closed_size = curr_size;
            let (pnl, is_profit) = calculate_pnl(position.is_long, curr_price, price, closed_size);
            
            // Remove entire old position from asset tracking
            update_asset_leverage(asset, curr_size, curr_lev, position.is_long, false);
            
            // Now flip into new side if there's remaining size
            let remaining_size = add_size - curr_size;
            if (remaining_size > 0) {
                position.size = remaining_size;
                position.leverage = leverage;
                position.is_long = is_long;
                position.entry_price = price;
                
                // Add new position to asset tracking
                update_asset_leverage(asset, remaining_size, lev, is_long, true);

                event::emit(Trade {
                    trader: address,
                    is_long: is_long,
                    size: added_size,
                    leverage: leverage,
                    used_margin: (added_size/lev)*100,
                    asset: type_info::type_name<T>(),
                    type: utf8(b"Reduce & Flip Side"),
                    entry_price: price,
                    fee: 0,
                    time: timestamp::now_seconds(),
                });

            } else {
                // Fully closed, no new position
                position.size = 0;
                position.leverage = 0;
                position.entry_price = 0;

                event::emit(Trade {
                    trader: address,
                    is_long: is_long,
                    size: added_size,
                    leverage: leverage,
                    used_margin: (added_size/lev)*100,
                    asset: type_info::type_name<T>(),
                    type: utf8(b"Close"),
                    entry_price: price,
                    fee: 0,
                    time: timestamp::now_seconds(),
                });

            };

            return (pnl, is_profit)
        } else {
            // Partial close
            let closed_size = add_size;
            let (pnl, is_profit) = calculate_pnl(position.is_long, curr_price, price, closed_size);

            position.size = (curr_size - add_size);
            // leverage & entry_price unchanged for remaining position

            // Remove closed portion from asset tracking
            update_asset_leverage(asset, closed_size, curr_lev, position.is_long, false);

                event::emit(Trade {
                    trader: address,
                    is_long: is_long,
                    size: added_size,
                    leverage: leverage,
                    used_margin: (added_size/lev)*100,
                    asset: type_info::type_name<T>(),
                    type: utf8(b"Partial Close"),
                    entry_price: price,
                    fee: 0,
                    time: timestamp::now_seconds(),
                });

            return (pnl, is_profit)
        }
    }

    fun update_asset_leverage(asset: &mut Asset,size: u256,leverage: u256,is_long: bool,is_add: bool) {
        
        if (is_long) {
            if (is_add) {
                // Adding to longs
                let current_weighted_lev = asset.longs * (asset.leverage as u256);
                let new_weighted_lev = current_weighted_lev + (size * leverage);
                asset.longs = asset.longs + size;
                asset.leverage = ((new_weighted_lev / asset.longs) as u64);
            } else {
                // Removing from longs
                let current_weighted_lev = asset.longs * (asset.leverage as u256);
                let removed_weighted_lev = size * leverage;
                
                // Prevent underflow
                if (asset.longs >= size) {
                    asset.longs = asset.longs - size;
                    if (asset.longs > 0) {
                        asset.leverage = (((current_weighted_lev - removed_weighted_lev) / asset.longs) as u64);
                    } else {
                        asset.leverage = 0;
                    }
                };
            }
        } else {
            if (is_add) {
                // Adding to shorts
                let current_weighted_lev = asset.shorts * (asset.leverage as u256);
                let new_weighted_lev = current_weighted_lev + (size * leverage);
                asset.shorts = asset.shorts + size;
                asset.leverage = ((new_weighted_lev / asset.shorts) as u64);
            } else {
                // Removing from shorts
                let current_weighted_lev = asset.shorts * (asset.leverage as u256);
                let removed_weighted_lev = size * leverage;
                
                // Prevent underflow
                if (asset.shorts >= size) {
                    asset.shorts = asset.shorts - size;
                    if (asset.shorts > 0) {
                        asset.leverage = (((current_weighted_lev - removed_weighted_lev) / asset.shorts) as u64);
                    } else {
                        asset.leverage = 0;
                    }
                };
            }
        }
    }

    fun calculate_pnl(is_long: bool, entry_price: u256, exit_price: u256, size: u256): (u256, bool) {
        if (is_long) {
            if (exit_price >= entry_price) {
                ((exit_price - entry_price) * size, true)
            } else {
                ((entry_price - exit_price) * size, false)
            }
        } else {
            if (entry_price >= exit_price) {
                ((entry_price - exit_price) * size, true)
            } else {
                ((exit_price - entry_price) * size, false)
            }
        }
    }


    public fun estimate_pnl<T: store>(position: &Position<T>, current_price: u256): (u256, bool) {
        if (position.size == 0) {
            return (0, true)
        };

        let entry_price: u256 = (position.entry_price as u256);
        let size: u256 = (position.size as u256);

        if (position.is_long) {
            if (current_price >= entry_price) {
                ((current_price - entry_price) * size, true)
            } else {
                ((entry_price - current_price) * size, false)
            }
        } else {
            if (entry_price >= current_price) {
                ((entry_price - current_price) * size, true)
            } else {
                ((current_price - entry_price) * size, false)
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
    public fun get_view_position<T: store + drop>(user: address): ViewPosition acquires UserBook {
        let user_book = borrow_global_mut<UserBook<T>>(@dev);

        let price = VerifiedTokens::get_coin_metadata_price(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));
        let denom = VerifiedTokens::get_coin_metadata_denom(&VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>()));

        if (!table::contains(&user_book.book, user)) {
            return ViewPosition {asset: type_info::type_name<T>(), used_margin: 0, usd_size: 0, size:0, entry_price:0, price: price, is_long:false, leverage:0, pnl: 0, is_profit: false, denom: denom, profit_fee: 0};
        };
        let position = table::borrow_mut(&mut user_book.book, user);
       // let coin_denom = VerifiedTokens::get_coin_denom<T>();
        let (pnl, is_profit) = estimate_pnl<T>(position, (price as u256));
        if(position.leverage == 0){
            position.leverage = 100;
        };
        ViewPosition {asset: type_info::type_name<T>(), used_margin: ((position.size as u256)*(position.entry_price as u256) / (position.leverage as u256)), usd_size: (position.size as u256)*(position.entry_price as u256),  size: position.size , entry_price: position.entry_price, price: price, is_long:position.is_long, leverage:position.leverage, pnl: pnl, is_profit: is_profit, denom: denom, profit_fee: 0}
    }

    #[view]
    public fun get_market(res: String): ViewAsset acquires AssetBook {
        let asset = borrow_global<AssetBook>(@dev);
        let t = table::borrow(&asset.book, res);
        let price = VerifiedTokens::get_coin_metadata_price(&VerifiedTokens::get_coin_metadata_by_res(res));
        let denom = VerifiedTokens::get_coin_metadata_denom(&VerifiedTokens::get_coin_metadata_by_res(res));
        let oi = (t.shorts+t.longs)*price;
        ViewAsset { asset: t.asset, shorts: t.shorts,  longs: t.longs, oi:oi, leverage: t.leverage, liquidity:0, utilization:0, price: price , denom: denom }
    }

    #[view]
    public fun get_market_list<T: store + drop>(): vector<String> acquires Markets {
      let markets = borrow_global<Markets>(@dev);
      markets.list
    }

    #[view]
    public fun get_all_markets(): vector<ViewAsset> acquires Markets, AssetBook {
        let markets = borrow_global<Markets>(@dev);
        let len = vector::length(&markets.list);
        let vect = vector::empty<ViewAsset>();
        while(len>0){
            let market = vector::borrow(&markets.list, len-1);
            vector::push_back(&mut vect, get_market(*market));
            len=len-1;
        };
        vect
    }

    #[view]
    public fun get_all_positions(address: address): vector<ViewPosition> acquires UserBook {
        vector[get_view_position<SuiBitcoin>(address),get_view_position<SuiSui>(address),get_view_position<SuiEthereum>(address)]
    }
}
