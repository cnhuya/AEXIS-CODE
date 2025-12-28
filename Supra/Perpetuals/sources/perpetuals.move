module dev::QiaraPerpsV40{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table;
    use std::timestamp;
    use std::bcs;
    use supra_framework::event;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraMarginV60::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRIV60::{Self as RI};

    use dev::QiaraTokensMetadataV51::{Self as TokensMetadata, VMetadata};
    use dev::QiaraTokensSharedV51::{Self as TokensShared};

    use dev::QiaraTokenTypesV30::{Self as TokensTypes};

    use dev::QiaraAutomationV8::{Self as auto, Access as AutoAccess};

    use dev::QiaraMathV9::{Self as QiaraMath};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_MARKET_ALREADY_EXISTS: u64 = 2;
    const ERROR_LEVERAGE_TOO_LOW: u64 = 3;
    const ERROR_SENDER_DOESNT_MATCH_SIGNER: u64 = 4;

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
        margin: MarginAccess,
        auto: AutoAccess,
    }

    struct Asset has store, key, drop{
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

    struct Position has copy, drop, store, key {
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
        book: Map<String, Asset>,
    }

    struct UserBook has key, store {
        book: table::Table<vector<u8>, Map<String, Position>>,
    }

    struct Markets has key, store{
        list: vector<String>
    }

// === EVENTS === //
    #[event]
    struct Trade has copy, drop, store {
        validator: address,
        trader: vector<u8>, // i.e shared storage?
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


/// === INIT ===
    fun init_module(admin: &signer) acquires Markets, AssetBook{

        if (!exists<Markets>(@dev)) {
            move_to(admin, Markets { list: vector::empty<String>()});
        };

        if (!exists<AssetBook>(@dev)) {
            move_to(admin, AssetBook { book: map::new<String, Asset>()});
        };

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { margin: Margin::give_access(admin), auto: auto::give_access(admin),});
        };

        create_market(admin, utf8(b"Bitcoin"));
        create_market(admin, utf8(b"Solana"));
        create_market(admin, utf8(b"Sui"));
        create_market(admin, utf8(b"Injective"));
        create_market(admin, utf8(b"Virtuals"));
        create_market(admin, utf8(b"Supra"));
        create_market(admin, utf8(b"Deepbook"));

    }


/// === ENTRY FUNCTIONS ===
    public entry fun create_market(admin: &signer, name: String) acquires Markets, AssetBook{
        TokensTypes::ensure_valid_token_nick_name(name);

        if (!exists<AssetBook>(@dev)) {
            move_to(admin, AssetBook { book: map::new<String, Asset>()});
        };

        let asset_book = borrow_global_mut<AssetBook>(@dev);

        if (!map::contains_key(&asset_book.book, &name)) {
            map::upsert(&mut asset_book.book, name, Asset { 
                asset: name,
                shorts: 0,
                longs: 0,
                leverage: 0,
            });
        };

        let markets = borrow_global_mut<Markets>(@dev);
        assert!(!vector::contains(&markets.list, &name),ERROR_MARKET_ALREADY_EXISTS);
        vector::push_back(&mut markets.list, name);
    }

    fun find_position(user: vector<u8>, name:String, user_book: &mut UserBook): &mut Position {
        if (!table::contains(&user_book.book, user)) {
            table::add(&mut user_book.book, user, map::new<String, Position>());
        };

        let user_map = table::borrow_mut(&mut user_book.book, user);
        if(!map::contains_key(user_map, &name)){
            map::upsert(user_map, name, Position {
                size: 0,
                entry_price: 0,
                is_long: false,
                leverage: 0,
            });
        };

        map::borrow_mut(user_map, &name)
    }

    fun find_asset(asset: String, asset_book: &mut AssetBook): &mut Asset {
        map::borrow_mut(&mut asset_book.book, &asset)
    }

    fun ttta(a: u64){
        abort(a);
    }



    // Native Interface
        public entry fun trade_limit(signer: &signer, sender: vector<u8>, shared_storage_owner: vector<u8>, shared_storage_name: String, asset: String, size:u256, leverage: u64,side:String) acquires Permissions {
            assert!(bcs::to_bytes(&signer::address_of(signer)) == sender, ERROR_SENDER_DOESNT_MATCH_SIGNER);
            TokensShared::assert_is_sub_owner(shared_storage_owner, shared_storage_name, sender);
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);

            let args = vector[
                bcs::to_bytes(&sender),
                bcs::to_bytes(&shared_storage_owner),
                bcs::to_bytes(&shared_storage_name),
                bcs::to_bytes(&asset),
                bcs::to_bytes(&leverage),
                bcs::to_bytes(&side),
            ];

            auto::register_automation(signer, shared_storage_owner, shared_storage_name,1, args, auto::give_permission(&borrow_global<Permissions>(@dev).auto))
        }

        public entry fun trade_util(signer: &signer, sender: vector<u8>, shared_storage_owner: vector<u8>, shared_storage_name: String, asset: String, size:u256, leverage: u64, type:String) acquires Permissions, AssetBook, UserBook{
            assert!(bcs::to_bytes(&signer::address_of(signer)) == sender, ERROR_SENDER_DOESNT_MATCH_SIGNER);
            TokensShared::assert_is_sub_owner(shared_storage_owner, shared_storage_name, sender);
            
            let position = find_position(sender, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset)); 

            if(type == utf8(b"flip") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size*2, leverage, false, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"flip") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size*2, leverage, true, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"close") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, true, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"close") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, false, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"double") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, true, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"double") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, false, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            };
        }

        public entry fun trade(signer: &signer, sender: vector<u8>, shared_storage_owner: vector<u8>, shared_storage_name: String, asset: String, size:u256, leverage: u64, limit: u256, side: String, type: String) acquires UserBook, AssetBook, Permissions {
            assert!(bcs::to_bytes(&signer::address_of(signer)) == sender, ERROR_SENDER_DOESNT_MATCH_SIGNER);
            TokensShared::assert_is_sub_owner(shared_storage_owner, shared_storage_name, sender);
            
            let position = find_position(sender, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);
            let is_long: bool = false;

            if(side == utf8(b"long")){
                is_long = true;
            } else if(side == utf8(b"short")){
                is_long = false;
            };

            let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, is_long, (price as u128), sender);
            handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );

        }
    // Permissioneless Interface
        public fun p_trade_limit(validator: &signer, sender: vector<u8>, shared_storage_owner: vector<u8>, shared_storage_name: String, asset: String, size:u256, leverage: u64,side:String, perm: Permission) acquires Permissions {
            TokensShared::assert_is_sub_owner(shared_storage_owner, shared_storage_name, sender);
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);

            let args = vector[
                bcs::to_bytes(&sender),
                bcs::to_bytes(&shared_storage_owner),
                bcs::to_bytes(&shared_storage_name),
                bcs::to_bytes(&asset),
                bcs::to_bytes(&leverage),
                bcs::to_bytes(&side),
            ];

            auto::register_automation(validator, shared_storage_owner, shared_storage_name,1, args, auto::give_permission(&borrow_global<Permissions>(@dev).auto))
        }

        public fun p_trade_util(validator: &signer,sender: vector<u8>, shared_storage_owner: vector<u8>, shared_storage_name: String, asset: String, size:u256, leverage: u64, type:String, perm: Permission) acquires Permissions, AssetBook, UserBook{
            TokensShared::assert_is_sub_owner(shared_storage_owner, shared_storage_name, sender);
            
            let position = find_position(sender, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset)); 

            if(type == utf8(b"flip") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size*2, leverage, false, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"flip") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size*2, leverage, true, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"close") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, true, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"close") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, false, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"double") && (position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, true, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            } else if(type == utf8(b"double") && (!position.is_long)){
                let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, false, (price as u128), sender);
                handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );
            };
        }

        public fun p_trade(validator: &signer,sender: vector<u8>, shared_storage_owner: vector<u8>, shared_storage_name: String, asset: String, size:u256, leverage: u64, limit: u256, side: String, type: String, perm: Permission) acquires UserBook, AssetBook, Permissions {
            TokensShared::assert_is_sub_owner(shared_storage_owner, shared_storage_name, sender);
            
            let position = find_position(sender, asset, borrow_global_mut<UserBook>(@dev));
            let asset_book = borrow_global_mut<AssetBook>(@dev);
            let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
            assert!(leverage >= 100, ERROR_LEVERAGE_TOO_LOW);
            let is_long: bool = false;

            if(side == utf8(b"long")){
                is_long = true;
            } else if(side == utf8(b"short")){
                is_long = false;
            };

            let (size_diff_usd, is_profit) = calculate_position(@0x0, asset, asset_book,position, size, leverage, is_long, (price as u128), sender);
            handle_pnl(asset, size_diff_usd, is_profit, shared_storage_owner, sender,shared_storage_name );

        }


/// === HELPER FUNCTIONS ===
    fun handle_pnl(asset: String, pnl: u256, is_profit: bool, shared_storage_owner: vector<u8>, sub_owner: vector<u8>, shared_storage_name: String) acquires Permissions {
        if (pnl == 0) { 
            return; 
        };
        
        if (is_profit) {
            Margin::add_credit(shared_storage_owner, shared_storage_name,sub_owner, pnl, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        } else {
            Margin::remove_credit(shared_storage_owner, shared_storage_name,sub_owner, pnl, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };
    }

    fun calculate_position(validator: address, assetName: String, asset_book: &mut AssetBook,position: &mut Position,added_size: u256,leverage: u64,is_long: bool,oracle_price: u128, address: vector<u8>): (u256, bool){
        let asset = find_asset(assetName, asset_book);

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
                validator: validator,
                trader: address,
                is_long: is_long,
                size: added_size,
                leverage: leverage,
                used_margin: (added_size/lev)*100,
                asset: assetName,
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
                validator: validator,
                trader: address,
                is_long: is_long,
                size: added_size,
                leverage: leverage,
                used_margin: (added_size/lev)*100,
                asset: assetName,
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
                    validator: validator,
                    trader: address,
                    is_long: is_long,
                    size: added_size,
                    leverage: leverage,
                    used_margin: (added_size/lev)*100,
                    asset: assetName,
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
                    validator: validator,
                    trader: address,
                    is_long: is_long,
                    size: added_size,
                    leverage: leverage,
                    used_margin: (added_size/lev)*100,
                    asset: assetName,
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
                    validator: validator,
                    trader: address,
                    is_long: is_long,
                    size: added_size,
                    leverage: leverage,
                    used_margin: (added_size/lev)*100,
                    asset: assetName,
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

    public fun estimate_pnl(position: &Position, current_price: u256): (u256, bool) {
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
    public fun get_positions(user: vector<u8>): Map<String, ViewPosition> acquires UserBook {
        let user_book = borrow_global_mut<UserBook>(@dev);


        let vect = map::new<String, ViewPosition>();
        if (!table::contains(&user_book.book, user)) {
            return vect
        };

        let user_map = table::borrow_mut(&mut user_book.book, user);
        let assets = map::keys(user_map);

        let len = vector::length(&assets);
        let i = 0;

        while(len>0){
            let asset = vector::borrow(&assets, i);
            let position = get_position(*asset, user);
            map::upsert(&mut vect, *asset, position);
            len=len-1;
        };

       return vect
    }

    #[view]
    public fun get_position(asset:String, user: vector<u8>): ViewPosition acquires UserBook {
        let user_book = borrow_global_mut<UserBook>(@dev);

        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(asset));

        if (!table::contains(&user_book.book, user)) {
            return ViewPosition {asset: asset, used_margin: 0, usd_size: 0, size:0, entry_price:0, price: price, is_long:false, leverage:0, pnl: 0, is_profit: false, denom: denom, profit_fee: 0};
        };

        let user_map = table::borrow_mut(&mut user_book.book, user);
        if(!map::contains_key(user_map, &asset)){
            return ViewPosition {asset: asset, used_margin: 0, usd_size: 0, size:0, entry_price:0, price: price, is_long:false, leverage:0, pnl: 0, is_profit: false, denom: denom, profit_fee: 0};
        };

        let position = map::borrow_mut(user_map, &asset);

        let (pnl, is_profit) = estimate_pnl(position, (price as u256));
        if(position.leverage == 0){
            position.leverage = 100;
        };
        ViewPosition {asset:asset, used_margin: ((position.size as u256)*(position.entry_price as u256) / (position.leverage as u256)), usd_size: (position.size as u256)*(position.entry_price as u256),  size: position.size , entry_price: position.entry_price, price: price, is_long:position.is_long, leverage:position.leverage, pnl: pnl, is_profit: is_profit, denom: denom, profit_fee: 0}
    }

    #[view]
    public fun get_market(asset: String): ViewAsset acquires AssetBook {
        let t = find_asset(asset, borrow_global_mut<AssetBook>(@dev));
        let price = TokensMetadata::get_coin_metadata_price(&TokensMetadata::get_coin_metadata_by_symbol(asset));
        let denom = TokensMetadata::get_coin_metadata_denom(&TokensMetadata::get_coin_metadata_by_symbol(asset));
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

}
