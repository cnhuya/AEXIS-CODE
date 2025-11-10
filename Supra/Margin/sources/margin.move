module dev::QiaraMarginV44{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use std::timestamp;
    use supra_oracle::supra_oracle_storage;

    use dev::QiaraVerifiedTokensV41::{Self as VerifiedTokens};
    use dev::QiaraFeeVaultV7::{Self as Fee};

    use dev::QiaraFeatureTypesV11::{Self as FeatureTypes};
    use dev::QiaraCoinTypesV11::{Self as CoinTypes};

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
        // adress, feature?, vault?
        holdings: table::Table<address, table::Table<String, vector<Credit>>>,
    }

    struct Leverage has key, store, copy, drop{
        usd_weight: u256,
        total_lev_usd: u256,
    }

    struct Credit has key, store, copy, drop{
        token: String,
        deposited: u256,
        borrowed: u256,
        locked: u256,
        rewards: u256,
        interest: u256,
        leverage: u64,
        reward_index_snapshot: u256,
        interest_index_snapshot: u256,
        last_update: u64,
    }

    struct FeaturesRegistry has key {
        features: vector<String>,
    }


// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<Leverage>(@dev)) {
            move_to(admin, Leverage { total_lev_usd: 0, usd_weight: 0 });
        };

        if (!exists<TokenHoldings>(@dev)) {
            move_to(admin,TokenHoldings {holdings: table::new<address, table::Table<String, vector<Credit>>>()});
        };

        if (!exists<FeaturesRegistry>(@dev)) {
            move_to(admin, FeaturesRegistry { features: vector::empty<String>() });
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

    public fun update_time<Token, Feature>(addr: address, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
        balance.last_update = timestamp::now_seconds() / 3600;
    }

    public fun update_interest_index<Token, Feature>(addr: address, index: u256, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
        balance.interest_index_snapshot = index;
    }

    public fun update_reward_index<Token, Feature>(addr: address, index: u256, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
        balance.reward_index_snapshot = index;
    }

    public fun update_leverage<Token, Feature>(addr: address, leverage: u64, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            balance.leverage = leverage;
        }
    }

    public fun add_deposit<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            balance.deposited = balance.deposited + value;
        };
    }

    public fun remove_deposit<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            if(value > balance.deposited){
                balance.deposited = 0
            } else {
                balance.deposited = balance.deposited - value;
            };
        };
    }

    public fun add_lock<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            balance.locked = balance.locked + value;
        };
    }

    public fun remove_lock<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            if(value > balance.locked){
                balance.locked = 0
            } else {
                balance.locked = balance.locked - value;
            };
        };
    }

    public fun add_borrow<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            balance.borrowed = balance.borrowed + value;
        };
    }

    public fun remove_borrow<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            if(value > balance.borrowed){
                balance.borrowed = 0
            } else {
                balance.borrowed = balance.borrowed - value;
            };
        };
    }


    public fun add_interest<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            balance.interest = balance.interest + value;
        }
    }

    public fun remove_interest<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            if(value > balance.interest){
                balance.interest = 0
            } else {
                balance.interest = balance.interest - value;
            }
        }
    }

    public fun add_rewards<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            balance.rewards = balance.rewards + value;
        }
    }

    public fun remove_rewards<Token, Feature>(addr: address, value: u256, cap: Permission) acquires TokenHoldings{
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
            if(value > balance.rewards){
                balance.rewards = 0
            } else {
                balance.rewards = balance.rewards - value;
            }
        }
    }

// === PUBLIC VIEWS === //

  /*  #[view]
    public fun get_list_of_vaults(res: String): vector<String> acquires VaultRegistry {
        return *table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, res)
    }*/

    #[view]
    public fun get_user_position_usd<Token, Feature>(addr: address): (u256, u256, u256, u256, u256, u256, u256, u256, u256, u256,u256)acquires TokenHoldings{

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
    }

#[view]
public fun get_user_total_usd(addr: address): (
    u256, u256, u256, u256, u256, u256, u256, u256, u256
) acquires TokenHoldings {
    let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
    let feature_registry = FeatureTypes::return_all_feature_types();

    let  total_lock = 0u256;
    let  total_dep = 0u256;
    let  total_margin = 0u256;
    let total_available = 0u256;
    let  total_bor = 0u256;
    let  total_rew = 0u256;
    let  total_int = 0u256;
    let  total_expected_interest = 0u256;

    let n = vector::length(&feature_registry);
    let  i = 0;

    while (i < n) {
        let feature = *vector::borrow(&feature_registry, i);

        if (!table::contains(&tokens_holdings.holdings, addr)) {
            i = i + 1;
            continue;
        };

        let user_holdings_ref = table::borrow_mut(&mut tokens_holdings.holdings, addr);
        if (!table::contains(user_holdings_ref, feature)) {
            i = i + 1;
            continue;
        };

        let holdings_ref = table::borrow_mut(user_holdings_ref, feature);
        let token_list = CoinTypes::return_all_coin_types();

        let num_tokens = vector::length(&token_list);
        let  y = 0;

        while (y < num_tokens) {
            let token_id = *vector::borrow(&token_list, y);
            let metadata = VerifiedTokens::get_coin_metadata_by_res(token_id);

            let price = (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
            let denom = (VerifiedTokens::get_coin_metadata_denom(&metadata) as u256);

            // skip if denom is 0
            if (denom == 0) {
                y = y + 1;
                continue;
            };

            let uv = find_balance(tokens_holdings, addr, token_id, feature);
            let leverage = if (uv.leverage == 0) 1 else uv.leverage;

            let dep_usd = uv.deposited * price / denom;
            let bor_usd = uv.borrowed  * price / (leverage as u256) / denom;
            let current_raw_borrow = uv.borrowed  * price / denom;
            let reward_usd = uv.rewards  * price / denom;
            let interest_usd = uv.interest  * price / denom;
            let lock_usd = uv.locked ;


            let utilization = if (current_raw_borrow == 0) 0
                else (bor_usd * 100) / current_raw_borrow;

            let (margin_interest, _, _) = QiaraMath::compute_rate(
                utilization,
                (VerifiedTokens::get_coin_metadata_market_rate(&metadata) as u256),
                (VerifiedTokens::get_coin_metadata_rate_scale(&metadata, false) as u256), // pridat check jestli to je borrow nebo lend
                false,
                5
            );

            total_lock = total_lock + lock_usd;
            total_dep = total_dep + dep_usd;
            total_margin = total_margin + (dep_usd * (((VerifiedTokens::get_coin_metadata_tier_efficiency(&metadata)) as u256)) / 10000);
            total_bor = total_bor + bor_usd;
            total_rew = total_rew + reward_usd;
            total_int = total_int + interest_usd;
            total_expected_interest = total_expected_interest + (margin_interest * dep_usd);

            y = y + 1;
        };

        i = i + 1;
    };

    let avg_interest = if (total_dep == 0) 0 else total_expected_interest / total_dep;
    let deducted_margin = if (total_margin > total_lock) { (total_margin - total_lock as u256) } else {0};

    (
        total_dep,
        deducted_margin,
        if (deducted_margin > total_bor) { deducted_margin - total_bor } else {0},
        total_bor,
        total_available,
        total_rew,
        total_int,
        avg_interest,
        total_lock
    )
}




    #[view]
    public fun get_user_balance<Token, Feature>(addr: address): Credit acquires TokenHoldings {
        return *find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>())
    }

    #[view]
    public fun get_user_raw_balance<Token, Feature>(addr: address): (String, u256, u256, u256, u256, u256, u256, u64) acquires TokenHoldings {
        let balance  = *find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<Token>(), type_info::type_name<Feature>());
        return (balance.token, balance.deposited, balance.borrowed, balance.rewards, balance.reward_index_snapshot, balance.interest, balance.interest_index_snapshot, balance.last_update)
    }

    #[view]
    public fun get_user_balances<Token, Feature>(addr: address): vector<Credit> acquires TokenHoldings {
        let th = borrow_global<TokenHoldings>(@dev);
        let inner = table::borrow(&th.holdings, addr);
        *table::borrow(inner, type_info::type_name<Feature>())
    }

// === MUT RETURNS === //
fun find_balance(feature_table: &mut TokenHoldings,addr: address,token: String,feature: String): &mut Credit {
    {
        if (!table::contains(&feature_table.holdings, addr)) {
            table::add(
                &mut feature_table.holdings,
                addr,
                table::new<String, vector<Credit>>(),
            );
        };
    };

    let user_holdings = table::borrow_mut(&mut feature_table.holdings, addr);

    {
        if (!table::contains(user_holdings, feature)) {
            table::add(
                user_holdings,
                feature,
                vector::empty<Credit>(),
            );
        };
    };

    let holdings = table::borrow_mut(user_holdings, feature);
    let len = vector::length(holdings);
    let i = 0;

    while (i < len) {
        let credit = vector::borrow_mut(holdings, i);
        if (credit.token == token) {
            return credit;
        };
        i = i + 1;
    };

    let new_credit = Credit {
        token,
        deposited: 0,
        borrowed: 0,
        locked: 0,
        rewards: 0,
        interest: 0,
        leverage: 1,
        reward_index_snapshot: 0,
        interest_index_snapshot: 0,
        last_update: 0,
    };
    vector::push_back(holdings, new_credit);

    let idx = vector::length(holdings) - 1;
    vector::borrow_mut(holdings, idx)
}

/*fun find_vault(vault_table: &mut Vaults, vault: String): &mut Vault {
    {
        if (!table::contains(&vault_table.vaults, vault)) {
            table::add(
                &mut vault_table.vaults,
                vault,
                Vault {
                    total_deposited: 0,
                    total_borrowed: 0,
                },
            );
        };
    };

    table::borrow_mut(&mut vault_table.vaults, vault)
}*/


// === HELPERS === //
    public fun is_user_registered(address: address): bool {
        if (!exists<TokenHoldings>(address)) {
            return false
        };

        if (!exists<FeaturesRegistry>(address)) {
            return false
        };
        return true
    }

    public fun get_utilization_ratio(addr: address): u256 acquires TokenHoldings{
        assert_user_registered(addr);
        let (_, marginUSD, _, borrowUSD, _, _, _, _, _, ) = get_user_total_usd(addr);
        if (marginUSD == 0) {
            0
        } else {
            ((borrowUSD * 100) / marginUSD as u256)
        }
    }

    public fun assert_user_registered(address: address) {
        assert!(!exists<TokenHoldings>(address), ERROR_USER_NOT_REGISTERED);
        assert!(!exists<FeaturesRegistry>(address), ERROR_USER_NOT_REGISTERED);
    }
}
