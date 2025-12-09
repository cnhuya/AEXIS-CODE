module dev::QiaraMarginV49{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table::{Self, Table};
    use std::timestamp;
    use supra_oracle::supra_oracle_storage;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraTokensMetadataV40::{Self as TokensMetadata};
    use dev::QiaraTokensSharedV40::{Self as TokensShared};

    use dev::QiaraTokenTypesV19::{Self as TokensType};
    use dev::QiaraMathV9::{Self as QiaraMath};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_USER_NOT_REGISTERED: u64 = 2;
    const ERROR_CANT_UPDATE_MARGIN_FOR_THIS_VAULT: u64 = 3;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 4;

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
        // address(shared storage owner), token, chain
        holdings: Table<vector<u8>, Table<String,Map<String, Credit>>>,
    }
    struct Credit has key, store, copy, drop{
        deposited: u256,
        borrowed: u256,
        staked: u256,
        rewards: u256,
        interest: u256,
        reward_index_snapshot: u256,
        interest_index_snapshot: u256,
        last_update: u64,
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

        if (!exists<TokenHoldings>(@dev)) {
            move_to(admin,TokenHoldings {holdings: table::new<vector<u8>, Table<String, Map<String, Credit>>>()});
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

    public fun update_time(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
        balance.last_update = timestamp::now_seconds() / 3600;
    }

    public fun update_interest_index(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, index: u256, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
        balance.interest_index_snapshot = index;
    }

    public fun update_reward_index(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, index: u256, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
        balance.reward_index_snapshot = index;
    }

    public fun add_deposit(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            balance.deposited = balance.deposited + value;
        };
    }

    public fun remove_deposit(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            if(value > balance.deposited){
                balance.deposited = 0
            } else {
                balance.deposited = balance.deposited - value;
            };
        };
    }

    public fun add_stake(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            balance.staked = balance.staked + value;
        };
    }

    public fun remove_stake(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            if(value > balance.staked){
                balance.staked = 0
            } else {
                balance.staked = balance.staked - value;
            };
        };
    }

    public fun add_borrow(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            balance.borrowed = balance.borrowed + value;
        };
    }

    public fun remove_borrow(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            if(value > balance.borrowed){
                balance.borrowed = 0
            } else {
                balance.borrowed = balance.borrowed - value;
            };
        };
    }


    public fun add_interest(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
           // tttta(14);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            balance.interest = balance.interest + value;
        }
    }

    public fun remove_interest(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            if(value > balance.interest){
                balance.interest = 0
            } else {
                balance.interest = balance.interest - value;
            }
        }
    }

    public fun add_rewards(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
          //              tttta(84877);
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            balance.rewards = balance.rewards + value;
        }
    }

    public fun remove_rewards(owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, value: u256, cap: Permission) acquires TokenHoldings{
        {
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
            if(value > balance.rewards){
                balance.rewards = 0
            } else {
                balance.rewards = balance.rewards - value;
            }
        }
    }

// === PUBLIC VIEWS === //

/*    #[view]
    public fun get_user_position_usd(owner: vector<u8>, token: ): (u256, u256, u256, u256, u256, u256, u256, u256, u256, u256,u256)acquires TokenHoldings{

        let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<Token>());

        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
        let raw_borrow = balance.borrowed ;

        let dep_usd = balance.deposited*(VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
        let bor_usd = balance.borrowed*(VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
        let reward_usd = balance.rewards*(VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
        let interest_usd = balance.interest*(VerifiedTokens::get_coin_metadata_price(&metadata) as u256);


        let utilization = if (raw_borrow == 0) 0 else (bor_usd * 100) / raw_borrow;
        let margin_interest = raw_borrow* (utilization * (VerifiedTokens::get_coin_metadata_min_lend_apr(&metadata) as u256))/ (VerifiedTokens::get_coin_metadata_denom(&metadata))/ 100;

        (dep_usd, bor_usd, raw_borrow, reward_usd, balance.locked , balance.reward_index_snapshot, interest_usd, balance.interest_index_snapshot, margin_interest, (balance.leverage as u256),( balance.last_update as u256))
    }*/

#[view]
public fun get_user_total_usd(owner: vector<u8>): (u256, u256, u256, u256, u256, u256, u256, u256, u256, vector<Credit>) acquires TokenHoldings {
    let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
    let tokens = TokensType::return_all_tokens();

    let  total_staked = 0u256;
    let  total_dep = 0u256;
    let  total_margin = 0u256;
    let  total_available = 0u256;
    let  total_bor = 0u256;
    let  total_rew = 0u256;
    let  total_int = 0u256;
    let  total_expected_interest = 0u256;

    let n = vector::length(&tokens);
    let i = 0;

    let vect = vector::empty<Credit>();

    while (i < n) {
        let token = *vector::borrow(&tokens, i);

        if (!table::contains(&tokens_holdings.holdings, owner)) {
            i = i + 1;
            continue;
        };

        let user_holdings_ref = table::borrow_mut(&mut tokens_holdings.holdings, owner);
        if (!table::contains(user_holdings_ref, token)) {
            i = i + 1;
            continue;
        };


        let holdings_ref = table::borrow_mut(user_holdings_ref, token);
        let chains = map::keys(holdings_ref);
        let values = map::values(holdings_ref);

        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
        let price = (TokensMetadata::get_coin_metadata_price(&metadata) as u256);
        let denom = (TokensMetadata::get_coin_metadata_denom(&metadata) as u256);

        let len_chain = vector::length(&chains);
        let y = 0;
        while (y < len_chain) {
            let value = *vector::borrow(&values, y);
            let chain = *vector::borrow(&chains, y);
            // skip if denom is 0
            if (denom == 0) {
                y = y + 1;
                continue;
            };

            let uv = find_balance(tokens_holdings, owner, token, chain);
            vector::push_back(&mut vect, *uv);
            let dep_usd = uv.deposited * price / denom;
            let bor_usd = uv.borrowed  * price / denom;
            let current_raw_borrow = uv.borrowed  * price / denom;
            let reward_usd = uv.rewards  * price / denom;
            let interest_usd = uv.interest  * price / denom;
            let staked_usd = uv.staked ;


            let utilization = if (current_raw_borrow == 0) 0
                else (bor_usd * 100) / current_raw_borrow;

            let (margin_interest, _, _) = QiaraMath::compute_rate(
                utilization,
                (TokensMetadata::get_coin_metadata_market_rate(&metadata) as u256),
                (TokensMetadata::get_coin_metadata_rate_scale(&metadata, false) as u256), // pridat check jestli to je borrow nebo lend
                false,
                5
            );

            total_staked = total_staked + staked_usd;
            total_dep = total_dep + dep_usd;
            total_margin = total_margin + (dep_usd * (((TokensMetadata::get_coin_metadata_tier_efficiency(&metadata)) as u256)) / 10000);
            total_bor = total_bor + bor_usd;
            total_rew = total_rew + reward_usd;
            total_int = total_int + interest_usd;
            total_expected_interest = total_expected_interest + (margin_interest * dep_usd);

            y = y + 1;
        };

        i = i + 1;
    };

    let avg_interest = if (total_dep == 0) 0 else total_expected_interest / total_dep;
    let deducted_margin = if (total_margin > total_staked) { (total_margin - total_staked as u256) } else {0};

    (
        total_dep,
        deducted_margin,
        if (deducted_margin > total_bor) { deducted_margin - total_bor } else {0},
        total_bor,
        total_available,
        total_rew,
        total_int,
        avg_interest,
        total_staked,
        vect
    )
}




    #[view]
    public fun get_user_balance(owner: vector<u8>, token: String, chain: String): Credit acquires TokenHoldings {
        return *find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain)
    }

    #[view]
    public fun get_user_raw_balance(owner: vector<u8>, token: String, chain: String): (u256, u256, u256, u256, u256, u256, u64) acquires TokenHoldings {
        let balance  = *find_balance(borrow_global_mut<TokenHoldings>(@dev),owner, token, chain);
        return (balance.deposited, balance.borrowed, balance.rewards, balance.reward_index_snapshot, balance.interest, balance.interest_index_snapshot, balance.last_update)
    }

    #[view]
    public fun get_user_balances(owner: vector<u8>, token: String, chain: String): Map<String, Credit> acquires TokenHoldings {
        let th = borrow_global<TokenHoldings>(@dev);
        let inner = table::borrow(&th.holdings, owner);
        *table::borrow(inner, token)
    }

// === MUT RETURNS === //
    fun find_balance(feature_table: &mut TokenHoldings,owner: vector<u8>,token: String,chain: String): &mut Credit {
        {
            if (!table::contains(&feature_table.holdings, owner)) {
                table::add(&mut feature_table.holdings,owner,table::new<String, Map<String, Credit>>(),);
            };
        };

        let user_holdings = table::borrow_mut(&mut feature_table.holdings, owner);

        {
            if (!table::contains(user_holdings, token)) {
                table::add(user_holdings,token,map::new<String, Credit>(),);
            };
        };

        let holdings = table::borrow_mut(user_holdings, token);

        let new_credit = Credit {
            deposited: 0,
            borrowed: 0,
            staked: 0,
            rewards: 0,
            interest: 0,
            reward_index_snapshot: 0,
            interest_index_snapshot: 0,
            last_update: 0,
        };

        if (!map::contains_key(holdings, &chain)) {
            map::upsert(holdings, chain, new_credit);
        };

        map::borrow_mut(holdings, &chain)
    }



// === HELPERS === //

    public fun get_utilization_ratio(owner: vector<u8>): u256 acquires TokenHoldings{
        let (_, marginUSD, _, borrowUSD, _, _, _, _, _, _,) = get_user_total_usd(addr);
        if (marginUSD == 0) {
            0
        } else {
            ((borrowUSD * 100) / marginUSD as u256)
        }
    }

}
