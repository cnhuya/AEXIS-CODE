module dev::QiaraMarginV7{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table::{Self, Table};
    use std::timestamp;
    use supra_oracle::supra_oracle_storage;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraTokensMetadataV5::{Self as TokensMetadata};
    use dev::QiaraSharedV1::{Self as TokensShared};

    use dev::QiaraTokenTypesV6::{Self as TokensType};
    
    use dev::QiaraMathV1::{Self as QiaraMath};
    use dev::QiaraGenesisV5::{Self as Genesis};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_USER_NOT_REGISTERED: u64 = 2;
    const ERROR_CANT_UPDATE_MARGIN_FOR_THIS_VAULT: u64 = 3;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 4;
    const ERROR_STAKE_LOCKED: u64 = 5;
    const ERROR_ARGUMENT_LENGHT_MISSMATCH: u64 = 6;

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
// === STRUCTS === //
    struct TokenHoldings has key {
        // shared_storage_name, token, chain, provider
        holdings: Table<String, Table<String,Map<String, Map<String, Credit>>>>,
        credit: Table<String, Integer>, // universal "credit" ($ value essentially), per user (shared_storage) | this is used for perpetual profits... and more in the future
    }

    struct StakeLock has key{
        map: Map<String, u64>,
    }

    struct Integer has drop, key, store, copy {
        value: u256,
        isPositive: bool,
    }

   // struct LockedFee has key, store {
   //     value: u128,
   //     last_claim: u64,
   // }

    struct Credit has key, store, copy, drop{
        deposited: u256,
        borrowed: u256,
        staked: u256,
        rewards: u256,
        interest: u256,
        reward_index_snapshot: u256,
        interest_index_snapshot: u256,
        last_update: u64,
        locked_fee: u256,
    }

    struct Leverage has key, store, copy, drop{
        usd_weight: u256,
        total_lev_usd: u256,
    }


// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<Leverage>(@dev)) {
            move_to(admin, Leverage { total_lev_usd: 0, usd_weight: 0 });
        };
        if (!exists<StakeLock>(@dev)) {
            move_to(admin, StakeLock { map: map::new<String, u64>() });
        };
        if (!exists<TokenHoldings>(@dev)) {
            move_to(admin,TokenHoldings {holdings: table::new<String, Table<String, Map<String, Map<String, Credit>>>>(), credit: table::new<String, Integer>()});
        };

    }

// === ENTRY FUN === //
    public fun update_global_l(amount: u64, leverage: u64, _cap: &Permission) acquires Leverage {
        let l = borrow_global_mut<Leverage>(@dev);

        assert!(amount > 0, 101);

        let amt = (amount as u256);
        let lev = (leverage as u256);

        l.usd_weight = l.usd_weight + amt;
        l.total_lev_usd = l.total_lev_usd + (amt * lev);
    }

    fun tttta(number: u64){
        abort(number);
    }

    public fun add_locked_fee(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            balance.locked_fee = balance.locked_fee + value;
        };
    }

    public fun remove_locked_fee(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            if(value > balance.locked_fee){
                balance.locked_fee = 0
            } else {
                balance.locked_fee = balance.locked_fee - value;
            };
        };
    }


    public fun add_credit(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name);
        credit.value = credit.value + value;
    }

    public fun remove_credit(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, value: u256, cap: Permission) acquires TokenHoldings {
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        let holdings = borrow_global_mut<TokenHoldings>(@dev);
        let credit = find_credit(holdings, shared_storage_name);

        if (credit.isPositive) {
            if (value > credit.value) {
                credit.value = value - credit.value;
                credit.isPositive = false;
            } else {
                credit.value = credit.value - value;
            };
        } else {
            credit.value = credit.value + value;
        };
    }

    // deprecated?
    public fun update_time(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String, provider: String, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
        balance.last_update = timestamp::now_seconds() / 3600;
    }

    public fun update_staked_time(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, cap: Permission) acquires StakeLock{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        let lock = find_stake_lock(&mut borrow_global_mut<StakeLock>(@dev).map,shared_storage_name);
        *lock = (Genesis::return_epoch() as u64);
    }

    public fun update_interest_index(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, index: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
        balance.interest_index_snapshot = index;
        balance.last_update = timestamp::now_seconds();
    }

    public fun update_reward_index(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, index: u256, cap: Permission) acquires TokenHoldings{
        //TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
        balance.reward_index_snapshot = index;
        balance.last_update = timestamp::now_seconds();
    }

    public fun add_deposit(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            balance.deposited = balance.deposited + value;
        };
    }

    public fun remove_deposit(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            if(value > balance.deposited){
                balance.deposited = 0
            } else {
                balance.deposited = balance.deposited - value;
            };
        };
    }

    public fun add_stake(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
      //  TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            balance.staked = balance.staked + value;
        };
    }

    public fun remove_stake(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: vector<String>, chain: vector<String>,provider: vector<String>, value: vector<u256>, cap: Permission) acquires StakeLock, TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        assert!(vector::length(&token) == vector::length(&chain) && vector::length(&token) == vector::length(&provider) && vector::length(&token) == vector::length(&value), ERROR_ARGUMENT_LENGHT_MISSMATCH);

        let lock = find_stake_lock(&mut borrow_global_mut<StakeLock>(@dev).map,shared_storage_name);
        assert!(*lock+2 <= (Genesis::return_epoch() as u64), ERROR_STAKE_LOCKED);

        let len = vector::length(&token);
        while(len>0){
            let token = vector::borrow(&token, len-1);
            let chain = vector::borrow(&chain, len-1);
            let provider = vector::borrow(&provider, len-1);
            let value = vector::borrow(&value, len-1);
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, *token, *chain, *provider);

            if(*value > balance.staked){
                balance.staked = 0
            } else {
                balance.staked = balance.staked - *value;
            };
            len = len-1
        };
    }

    public fun add_borrow(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            balance.borrowed = balance.borrowed + value;
        };
    }

    public fun remove_borrow(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            if(value > balance.borrowed){
                balance.borrowed = 0
            } else {
                balance.borrowed = balance.borrowed - value;
            };
        };
    }


    public fun add_interest(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
           // tttta(14);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            balance.interest = balance.interest + value;
        }
    }

    public fun remove_interest(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            if(value > balance.interest){
                balance.interest = 0
            } else {
                balance.interest = balance.interest - value;
            }
        }
    }

    public fun add_rewards(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
          //              tttta(84877);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            balance.rewards = balance.rewards + value;
        }
    }

    public fun remove_rewards(owner: vector<u8>, shared_storage_name: String, sub_owner: vector<u8>, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires TokenHoldings{
        TokensShared::assert_is_sub_owner(owner, shared_storage_name, sub_owner);
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
            if(value > balance.rewards){
                balance.rewards = 0
            } else {
                balance.rewards = balance.rewards - value;
            }
        }
    }

// === PUBLIC VIEWS === //

    #[view]
    public fun get_user_total_usd(shared_storage_name: String): (u256, u256, u256, u256, u256, u256, u256, u256, u256, u256, vector<Credit>) acquires TokenHoldings {
        let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
        let tokens = TokensType::return_full_nick_names_list();

        let total_staked = 0u256;
        let total_dep = 0u256;
        let total_margin = 0u256;
        let total_available = 0u256;
        let total_bor = 0u256;
        let total_rew = 0u256;
        let total_int = 0u256;
        let total_locked_fees = 0u256;
        let total_expected_interest = 0u256;

        let len_tokens = vector::length(&tokens);
        let i = 0;
        let vect = vector::empty<Credit>();

        while (i < len_tokens) {
            let token = *vector::borrow(&tokens, i);

            if (!table::contains(&tokens_holdings.holdings, shared_storage_name)) {
                i = i + 1;
                continue;
            };

            // Get Metadata once per token type
            let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
            let price = (TokensMetadata::get_coin_metadata_price(&metadata) as u256);
            let denom = (TokensMetadata::get_coin_metadata_denom(&metadata) as u256);
            let efficiency = (TokensMetadata::get_coin_metadata_tier_efficiency(&metadata) as u256);

            // Pre-collect keys to avoid borrow conflicts
            let vect_chain = vector::empty<String>();
            let vect_provider = vector::empty<String>();

            {
                let user_holdings_ref = table::borrow(&tokens_holdings.holdings, shared_storage_name);
                if (!table::contains(user_holdings_ref, token)) {
                    i = i + 1;
                    continue;
                };

                let chain_map = table::borrow(user_holdings_ref, token);
                let chains = map::keys(chain_map);
                let len_chain = vector::length(&chains);
                let y = 0;
                while (y < len_chain) {
                    let chain = *vector::borrow(&chains, y);
                    let providers_map = map::borrow(chain_map, &chain);
                    let providers = map::keys(providers_map);
                    let len_providers = vector::length(&providers);
                    let x = 0;
                    while (x < len_providers) {
                        vector::push_back(&mut vect_chain, chain);
                        vector::push_back(&mut vect_provider, *vector::borrow(&providers, x));
                        x = x + 1;
                    };
                    y = y + 1;
                };
            };

            // Process collected items for this token
            let j = 0;
            let len_inner = vector::length(&vect_chain);
            while (j < len_inner) {
                let chain_copy = *vector::borrow(&vect_chain, j);
                let provider_copy = *vector::borrow(&vect_provider, j);
                
                let uv_ref = find_balance(tokens_holdings, shared_storage_name, token, chain_copy, provider_copy);
                let uv = *uv_ref;
                vector::push_back(&mut vect, uv);

                // Safety check for division
                if (denom > 0) {
                    let dep_usd = (uv.deposited * price) / denom;
                    let bor_usd = (uv.borrowed * price) / denom;
                    let reward_usd = (uv.rewards * price) / denom;
                    let interest_usd = (uv.interest * price) / denom;
                    let locked_fees_usd = ((uv.locked_fee as u256) * price) / denom;

                    // FIXED: Using a helper variable to avoid 'let' shadowing bugs
                    let current_staked_usd: u256;
                    if (token == utf8(b"Qiara")) {
                        current_staked_usd = uv.staked / denom;
                    } else {
                        current_staked_usd = (uv.staked * price) / denom;
                    };

                    // Accumulate totals
                    total_staked = total_staked + current_staked_usd;
                    total_dep = total_dep + dep_usd;
                    total_bor = total_bor + bor_usd;
                    total_rew = total_rew + reward_usd;
                    total_int = total_int + interest_usd;
                    total_locked_fees = total_locked_fees + locked_fees_usd;
                    total_margin = total_margin + (dep_usd * efficiency / 10000);
                };
                j = j + 1;
            };
            i = i + 1;
        };

        // Credit Processing (Calculated once outside token loop to avoid inflation)
        let credit = find_credit(tokens_holdings, shared_storage_name);
        if (credit.isPositive) {
            total_available = total_available + credit.value;
            total_margin = total_margin + credit.value;
        } else {
            total_available = if (total_available > credit.value) { total_available - credit.value } else { 0 };
            total_margin = if (total_margin > credit.value) { total_margin - credit.value } else { 0 };
        };

        let avg_interest = if (total_dep == 0) 0 else total_expected_interest / total_dep;
        let deducted_margin = if (total_margin > total_staked) { total_margin - total_staked } else { 0 };

        (
            total_dep,
            deducted_margin,
            if (deducted_margin > total_bor) { deducted_margin - total_bor } else { 0 },
            total_bor,
            total_available,
            total_rew,
            total_int,
            avg_interest,
            total_staked,
            total_locked_fees,
            vect
        )
    }

    #[view]
    public fun get_user_total_staked_usd(shared_storage_name: String): u256 acquires TokenHoldings {
        let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
        let tokens = TokensType::return_full_nick_names_list();
        let total_staked_usd = 0u256;

        let len_tokens = vector::length(&tokens);
        let i = 0;

        while (i < len_tokens) {
            let token = *vector::borrow(&tokens, i);

            if (!table::contains(&tokens_holdings.holdings, shared_storage_name)) {
                i = i + 1;
                continue;
            };

            // Get Metadata for price/denom
            let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
            let price = (TokensMetadata::get_coin_metadata_price(&metadata) as u256);
            let denom = (TokensMetadata::get_coin_metadata_denom(&metadata) as u256);

            // Pre-collect keys (standard pattern to avoid double-borrowing table/map)
            let vect_chain = vector::empty<String>();
            let vect_provider = vector::empty<String>();

            {
                let user_holdings_ref = table::borrow(&tokens_holdings.holdings, shared_storage_name);
                if (!table::contains(user_holdings_ref, token)) {
                    i = i + 1;
                    continue;
                };

                let chain_map = table::borrow(user_holdings_ref, token);
                let chains = map::keys(chain_map);
                let len_chain = vector::length(&chains);
                let y = 0;
                while (y < len_chain) {
                    let chain = *vector::borrow(&chains, y);
                    let providers_map = map::borrow(chain_map, &chain);
                    let providers = map::keys(providers_map);
                    let len_providers = vector::length(&providers);
                    let x = 0;
                    while (x < len_providers) {
                        vector::push_back(&mut vect_chain, chain);
                        vector::push_back(&mut vect_provider, *vector::borrow(&providers, x));
                        x = x + 1;
                    };
                    y = y + 1;
                };
            };

            // Process collected items and sum USD value
            let j = 0;
            let len_inner = vector::length(&vect_chain);
            while (j < len_inner) {
                let chain_copy = *vector::borrow(&vect_chain, j);
                let provider_copy = *vector::borrow(&vect_provider, j);
                
                let uv = *find_balance(tokens_holdings, shared_storage_name, token, chain_copy, provider_copy);

                if (denom > 0) {
                    let current_staked_usd: u256;
                    // Check for your specific Qiara token logic
                    if (token == utf8(b"Qiara")) {
                        current_staked_usd = uv.staked / denom;
                    } else {
                        current_staked_usd = (uv.staked * price) / denom;
                    };
                    total_staked_usd = total_staked_usd + current_staked_usd;
                };
                j = j + 1;
            };
            i = i + 1;
        };

        total_staked_usd
    }

    #[view]
    public fun get_user_balance(shared_storage_name: String, token: String, chain: String , provider: String,): Credit acquires TokenHoldings {
        return *find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider)
    }

    #[view]
    public fun get_user_raw_balance(shared_storage_name: String, token: String, chain: String, provider: String): (u256, u256,u256, u256, u256, u256, u256, u256, u64) acquires TokenHoldings {
        let balance  = *find_balance(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name, token, chain, provider);
        return (balance.deposited, balance.borrowed, balance.staked, balance.rewards, balance.reward_index_snapshot, balance.interest, balance.interest_index_snapshot, balance.locked_fee, balance.last_update)
    }

    #[view]
    public fun get_user_balances(shared_storage_name: String, token: String): Map<String, Map<String, Credit>> acquires TokenHoldings {
        let th = borrow_global<TokenHoldings>(@dev);
        let inner = table::borrow(&th.holdings, shared_storage_name);
        *table::borrow(inner, token)
    }

    #[view]
    public fun get_user_credit(shared_storage_name: String,): (u256, bool) acquires TokenHoldings {
        let credit = *find_credit(borrow_global_mut<TokenHoldings>(@dev),shared_storage_name);
        return (credit.value, credit.isPositive)
    }

    #[view]
    public fun get_user_stake_lock(shared_storage_name: String,): u64 acquires StakeLock {
        let lock = *find_stake_lock(&mut borrow_global_mut<StakeLock>(@dev).map,shared_storage_name);
        return lock
    }

// === MUT RETURNS === //
    fun find_balance(feature_table: &mut TokenHoldings,shared_storage_name: String,token: String,chain: String, provider: String,): &mut Credit {
        {
            if (!table::contains(&feature_table.holdings, shared_storage_name)) {
                table::add(&mut feature_table.holdings,shared_storage_name,table::new<String, Map<String, Map<String, Credit>>>(),);
            };
        };

        let user_holdings = table::borrow_mut(&mut feature_table.holdings, shared_storage_name);

        {
            if (!table::contains(user_holdings, token)) {
                table::add(user_holdings,token, map::new<String, Map<String, Credit>>(),);
            };
        };

        let holdings = table::borrow_mut(user_holdings, token);

        if (!map::contains_key(holdings, &chain)) {
            map::upsert(holdings, chain, map::new<String, Credit>());
        };

        let a = map::borrow_mut(holdings, &chain);

        let new_credit = Credit {
            deposited: 0,
            borrowed: 0,
            staked: 0,
            rewards: 0,
            interest: 0,
            reward_index_snapshot: 0,
            interest_index_snapshot: 0,
            last_update: 0,
            locked_fee: 0
        };

        if (!map::contains_key(a, &provider)) {
            map::upsert(a, provider, new_credit);
        };

        map::borrow_mut(a, &provider)
    }

    fun find_stake_lock(map: &mut Map<String, u64>, shared_storage_name: String): &mut u64 {
        if (!map::contains_key(map, &shared_storage_name)) {
            map::upsert(map, shared_storage_name, 0);
        };
        return map::borrow_mut(map, &shared_storage_name)
    }

    fun find_credit(feature_table: &mut TokenHoldings,shared_storage_name: String): &mut Integer {
        {
            if (!table::contains(&feature_table.credit, shared_storage_name)) {
                table::add(&mut feature_table.credit, shared_storage_name, Integer { value: 0, isPositive: true });
            };
        };

        return table::borrow_mut(&mut feature_table.credit, shared_storage_name)
    }



// === HELPERS === //

    public fun get_utilization_ratio(shared_storage_name: String): u256 acquires TokenHoldings{
        let (_, marginUSD, _, borrowUSD, _, _, _, _, _, _,_,) = get_user_total_usd(shared_storage_name);
        if (marginUSD == 0) {
            0
        } else {
            ((borrowUSD * 100) / marginUSD as u256)
        }
    }

}
