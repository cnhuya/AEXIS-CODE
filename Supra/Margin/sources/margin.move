module dev::QiaraMarginV1{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use dev::QiaraVerifiedTokensV1::{Self as Factory, Tier, CoinData, Metadata};
    use dev::QiaraMath::{Self as Math};
    

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NO_USER_BALANCE_REGISTERED: u64 = 2;
    const ERROR_NOT_REGISTERED: u64 = 3;


    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(s: &signer, access: &Access): Permission {
        Permission {}
    }

    struct TokenHoldings has key {
        holdings: table::Table<String, vector<Balance>>,
    }

    struct Balance has key, store, copy, drop {
        token: String,
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
        last_update: u64
    }

    struct StorageRegistry has key {
        list: vector<String>,
    }


    /// ========== INIT ==========
    fun init_module(admin: &signer){
    }

    public entry fun init_user(user: &signer) {
        if (!exists<TokenHoldings>(signer::address_of(user))) {
            move_to(user, TokenHoldings { holdings: table::new<String,vector<Balance>>()});
        };

        if (!exists<StorageRegistry>(signer::address_of(user))) {
            move_to(user, StorageRegistry { list: vector::empty<String>()});
        };
    }

    public fun add_balance<T, X>(admin: &signer, to: address, value: u64, isDeposit: bool, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(to), type_info::type_name<T>(), type_info::type_name<X>());
        if(isDeposit){
            balance.deposited = balance.deposited + value;
        } else{
            balance.borrowed = balance.borrowed + value;
        }
    }

    public fun remove_balance<T, X>(admin: &signer, to: address, value: u64, isDeposit: bool, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(to), type_info::type_name<T>(), type_info::type_name<X>());
        if(isDeposit){
            if(value > balance.deposited){
                balance.deposited = 0
            } else {
                balance.deposited = balance.deposited - value;
            }
        } else{
            if(value > balance.deposited){
                balance.borrowed = 0
            } else {
                balance.borrowed = balance.borrowed - value;
            }
        }
    }


    #[view]
    public fun get_user_position_usd<T,X>(addr: address): (u256, u256, u256, u256) acquires TokenHoldings, StorageRegistry  {
        let tokens_holdings = borrow_global_mut<TokenHoldings>(addr);
        let tokens_registry = borrow_global_mut<StorageRegistry>(addr);

        // lookup oracle metadata
        let metadata = Factory::get_coin_metadata_by_res(&type_info::type_name<T>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        
        // normalize amount * price / 10^coin_decimals
        let denom = Math::pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

        let uv = find_balance(borrow_global_mut<TokenHoldings>(addr), type_info::type_name<T>(), type_info::type_name<X>());

        let dep_usd = ((((uv.deposited as u256) * (price as u256)) / denom)*(Factory::lend_ratio(Factory::get_coin_metadata_tier(&metadata)) as u256))/100;
        let bor_usd = ((uv.borrowed as u256)  * (price as u256)) / denom;
        let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
        let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

        (dep_usd, bor_usd, reward_usd ,interest_usd)
    }

    #[view]
    public fun get_user_total_usd(addr: address): (u256, u256, u256, u256) acquires StorageRegistry, TokenHoldings{
        let tokens_holdings = borrow_global_mut<TokenHoldings>(addr);
        let storage_registry = borrow_global_mut<StorageRegistry>(addr);

        let total_dep = 0u256;
        let total_bor = 0u256;
        let total_rew = 0u256;
        let total_int = 0u256;

        let n = vector::length(&storage_registry.list);
        let i = 0;
        while (i < n) {
            let holdings = *table::borrow(&tokens_holdings.holdings, *vector::borrow(&storage_registry.list, i));
            let x = vector::length(&holdings);  
            let y = 0;   
            while (y < x) {
                let holding = *vector::borrow(&holdings, y);
                let uv = find_balance(tokens_holdings, holding.token, *vector::borrow(&storage_registry.list, i));    
                let metadata = Factory::get_coin_metadata_by_res(&uv.token);
                let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));

                // denominator = 10^(coin_decimals + price_decimals)
                let denom = Math::pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

                // deposited/borrowed value in USD
                let dep_usd = ((uv.deposited as u256) * (price as u256)) / denom;
                let bor_usd = ((uv.borrowed  as u256) * (price as u256)) / denom;
                let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
                let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

                // apply lend rate (assumed %)
                total_dep = total_dep + (dep_usd * (Factory::lend_ratio(Factory::get_coin_metadata_tier(&metadata)) as u256))/100;
                total_bor = total_bor + bor_usd;
                total_rew = total_rew + reward_usd;
                total_int = total_int + interest_usd;
                y = y + 1;
                };
            i = i + 1;
            };
        (total_dep, total_bor, total_rew, total_int)
    }

    fun find_balance(tokens_holdings: &mut TokenHoldings, token: String, vault: String): &mut Balance {
        if (!table::contains(&tokens_holdings.holdings, vault)) {
            table::add(&mut tokens_holdings.holdings, vault, vector::empty<Balance>());
        };

        let holdings = table::borrow_mut(&mut tokens_holdings.holdings, vault);
        let len = vector::length(holdings);
        let i = 0;

        while (i < len) {
            let balance = vector::borrow_mut(holdings, i);
            if (balance.token == token) {
                return balance;
            };
            i = i + 1;
        };

        let new_balance = Balance {
            token: token,
            deposited: 0,
            borrowed: 0,
            rewards: 0,
            interest: 0,
            last_update: 0,
        };
        vector::push_back(holdings, new_balance);
        let idx = vector::length(holdings) - 1;
        vector::borrow_mut(holdings, idx)
    }

    public fun is_user_registered(address: address): bool {
        if (!exists<TokenHoldings>(address)) {
            return false
        };

        if (!exists<StorageRegistry>(address)) {
            return false
        };
        return true
    }
}
