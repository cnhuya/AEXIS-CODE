module dev::QiaraMarginV28{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use std::timestamp;
    use supra_oracle::supra_oracle_storage;

    use dev::QiaraVerifiedTokensV15::{Self as VerifiedTokens, Tier, CoinData, Metadata};

    use dev::QiaraFeatureTypesV5::{Self as FeatureTypes};
    use dev::QiaraVaultTypesV5::{Self as VaultTypes};

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
        holdings: table::Table<address, table::Table<String, table::Table<String, vector<Balance>>>>,
        credits: table::Table<address, table::Table<String, Credit>>,
    }

    struct Vaults has key {
        vaults: table::Table<String, Vault>,
    }

    struct Vault has key, store, copy, drop{
        total_deposited: u128,
        total_borrowed: u128,
    }

    struct Leverage has key, store, copy, drop{
        usd_weight: u256,
        total_lev_usd: u256,
    }

    struct Credit has key, store, copy, drop{
        token: String,
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
        leverage: u64,
    }

    struct Balance has key, store, copy, drop {
        token: String,
        deposited: u64,
        borrowed: u64,
        reward_index_snapshot: u128,
        interest_index_snapshot: u128,
        last_update: u64,
    }

    struct VaultRegistry has key {
        vaults: table::Table<String, vector<String>>,
    }

    struct FeaturesRegistry has key {
        features: vector<String>,
    }

    struct UserVaults has key{
        provider: String,
        vaults: vector<Balance>,
    }

// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<Vaults>(@dev)) {
            move_to(admin, Vaults { vaults: table::new<String, Vault>() });
        };
        if (!exists<Leverage>(@dev)) {
            move_to(admin, Leverage { total_lev_usd: 0, usd_weight: 0 });
        };

        if (!exists<TokenHoldings>(@dev)) {
            move_to(admin,TokenHoldings {holdings: table::new<address, table::Table<String, table::Table<String, vector<Balance>>>>(),credits: table::new<address, table::Table<String, Credit>>()});
        };

        if (!exists<VaultRegistry>(@dev)) {
            move_to(admin,VaultRegistry {vaults: table::new<String, vector<String>>()});
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

    public fun update_time<T, X, Y>(addr: address, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
        balance.last_update = timestamp::now_seconds() / 3600;
    }

    public fun update_interest_index<T, X, Y>(addr: address, index: u128, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
        balance.interest_index_snapshot = index;
    }

    public fun update_reward_index<T, X, Y>(addr: address, index: u128, cap: Permission) acquires TokenHoldings{
        let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
        balance.reward_index_snapshot = index;
    }

    public fun update_leverage<T>(addr: address, leverage: u64, cap: Permission) acquires TokenHoldings{
        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            credit.leverage = leverage;
        }
    }

    public fun add_deposit<T, X, Y>(addr: address, value: u64, cap: Permission) acquires TokenHoldings, Vaults{
        {
           let vault = find_vault(borrow_global_mut<Vaults>(@dev), type_info::type_name<T>()); 
           vault.total_deposited = vault.total_deposited + (value as u128);
        };
        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
            balance.deposited = balance.deposited + value;
        };

        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            credit.deposited = credit.deposited + value;
        };
    }

    public fun remove_deposit<T, X, Y>(addr: address, value: u64, cap: Permission) acquires TokenHoldings, Vaults{
        {
           
           let vault = find_vault(borrow_global_mut<Vaults>(@dev), type_info::type_name<T>()); 
          // tttta((vault.total_deposited  as u64));
           vault.total_deposited = vault.total_deposited - (value as u128);
          // tttta(value);
        };

        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
            if(value > balance.borrowed){
                balance.deposited = 0
            } else {
                balance.deposited = balance.deposited - value;
            };
        };

        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            if(value > credit.deposited){
                credit.deposited = 0
            } else {
                credit.deposited = credit.deposited - value;
            };
        };
    }

    public fun add_borrow<T, X, Y>(addr: address, value: u64, cap: Permission) acquires TokenHoldings, Vaults{
        {
           let vault = find_vault(borrow_global_mut<Vaults>(@dev), type_info::type_name<T>()); 
           vault.total_borrowed + (value as u128);
        };

        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
            balance.borrowed = balance.borrowed + value;
        };

        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            credit.borrowed = credit.borrowed + value;
        };
    }

    public fun remove_borrow<T, X, Y>(addr: address, value: u64, cap: Permission) acquires TokenHoldings, Vaults{
        {
           let vault = find_vault(borrow_global_mut<Vaults>(@dev), type_info::type_name<T>()); 
           vault.total_borrowed - (value as u128);
        };

        {
            let balance = find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
            if(value > balance.borrowed){
                balance.borrowed = 0
            } else {
                balance.borrowed = balance.borrowed - value;
            };
        };

        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            if(value > credit.borrowed){
                credit.borrowed = 0
            } else {
                credit.borrowed = credit.borrowed - value;
            };
        };
    }

    public fun add_interest<T>(addr: address, value: u64, cap: Permission) acquires TokenHoldings{
        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            credit.interest = credit.interest + value;
        }
    }

    public fun remove_interest<T>(addr: address, value: u64, cap: Permission) acquires TokenHoldings{
        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            if(value > credit.interest){
                credit.interest = 0
            } else {
                credit.interest = credit.interest - value;
            }
        }
    }

    public fun add_rewards<T>(addr: address, value: u64, cap: Permission) acquires TokenHoldings{
        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            credit.rewards = credit.rewards + value;
        }
    }

    public fun remove_rewards<T>(addr: address, value: u64, cap: Permission) acquires TokenHoldings{
        {
            let credit = find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
            if(value > credit.rewards){
                credit.rewards = 0
            } else {
                credit.rewards = credit.rewards - value;
            }
        }
    }

// === PUBLIC VIEWS === //

    #[view]
    public fun get_list_of_vaults(res: String): vector<String> acquires VaultRegistry {
        return *table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, res)
    }

    #[view]
    public fun get_user_position_usd<T, X, Y>(addr: address): (u256, u256, u256, u256, u256, u256)acquires TokenHoldings{

        let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());

        // Scope 1: use balance
        let dep_usd;
        let bor_usd;
        let raw_borrow;
        {
            let uv = find_credit(tokens_holdings,addr, type_info::type_name<T>());

            dep_usd = (((uv.deposited as u256)* (VerifiedTokens::get_coin_metadata_price(&metadata) as u256))* (VerifiedTokens::lend_ratio(VerifiedTokens::get_coin_metadata_tier(&metadata)) as u256)) / 100;
            bor_usd = ((uv.borrowed as u256)* (VerifiedTokens::get_coin_metadata_price(&metadata) as u256)/ (uv.leverage as u256));
            raw_borrow = (uv.borrowed as u256)* (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
        };

        // Scope 2: use credit
        let reward_usd;
        let interest_usd;
        {
            let credit = find_credit(tokens_holdings,addr, type_info::type_name<T>());

            reward_usd = (credit.rewards as u256)* (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
            interest_usd = (credit.interest as u256)* (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
        };

        let utilization = if (raw_borrow == 0) 0 else (bor_usd * 100) / raw_borrow;
        let margin_interest = raw_borrow* (utilization * (VerifiedTokens::apr_increase(VerifiedTokens::get_coin_metadata_tier(&metadata)) as u256))/ (VerifiedTokens::get_coin_metadata_denom(&metadata))/ 100;

        (dep_usd, bor_usd, raw_borrow, reward_usd, interest_usd, margin_interest)
    }

    #[view]
    public fun get_user_total_usd(addr: address): (u256, u256, u256, u256, u256, u256) acquires  TokenHoldings {
        let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
        let feature_registry = FeatureTypes::return_all_feature_types();

        let  total_dep = 0u256;
        let  total_bor = 0u256;
        let  raw_borrow = 0u256;
        let  total_rew = 0u256;
        let  total_int = 0u256;
        let  utilization = 0u256;
        let  total_expected_interest = 0u256;

        let n = vector::length(&feature_registry);
        let i = 0;

        // search through features
        while (i < n) {
            let feature = vector::borrow(&feature_registry, i);
            let vaults = FeatureTypes::return_all_feature_types();
            let a = vector::length(&vaults);
            let  b = 0;

            // search through vaults
            while (b < a) {
                let vault = vector::borrow(&vaults, b);

                // First, collect tokens without holding references
                let feature_str = *feature;
                let vault_str = *vault;

                let token_list = {
                    let user_holdings_ref = table::borrow(&tokens_holdings.holdings, addr);
                    let holdings_ref = table::borrow(user_holdings_ref, feature_str);
                    if (table::contains(holdings_ref, vault_str)) {
                        let balances = table::borrow(holdings_ref, vault_str);
                        let len = vector::length(balances);
                        let  j = 0;
                        let  tokens = vector::empty<String>();
                        while (j < len) {
                            let holding = vector::borrow(balances, j);
                            vector::push_back(&mut tokens, holding.token);
                            j = j + 1;
                        };
                        tokens
                    } else {
                        vector::empty<String>()
                    }
                };

                // Process each token separately
                let num_tokens = vector::length(&token_list);
                let  y = 0;
                while (y < num_tokens) {
                    let token_id = *vector::borrow(&token_list, y);
                    let metadata = VerifiedTokens::get_coin_metadata_by_res(token_id);
                    // Scope 1: borrow balance
                    let dep_usd;
                    let bor_usd;
                    let current_raw_borrow;
                    {
                        let uv = find_credit(tokens_holdings,addr, token_id);
                        let metadata = VerifiedTokens::get_coin_metadata_by_res(uv.token);
                        dep_usd = ((uv.deposited as u256) * (VerifiedTokens::get_coin_metadata_price(&metadata) as u256)* (VerifiedTokens::lend_ratio(VerifiedTokens::get_coin_metadata_tier(&metadata)) as u256)) / 100;
                        bor_usd = ((uv.borrowed as u256) * (VerifiedTokens::get_coin_metadata_price(&metadata) as u256)/ (uv.leverage as u256));
                        current_raw_borrow = (uv.borrowed as u256)* (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
                    };

                    // Scope 2: borrow credit
                    let reward_usd;
                    let interest_usd;
                    {
                        let credit = find_credit(tokens_holdings,addr, token_id);
                        reward_usd = (credit.rewards as u256) * (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
                        interest_usd = (credit.interest as u256) * (VerifiedTokens::get_coin_metadata_price(&metadata) as u256);
                    };

                    // Safe utilization calc
                    if (current_raw_borrow == 0) {
                        utilization = 0;
                    } else {
                        utilization = (bor_usd * 100) / current_raw_borrow;
                    };

                    let (margin_interest, _, _) = QiaraMath::compute_rate(
                        (utilization as u256),
                        (VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate(token_id)) as u256),
                        (VerifiedTokens::rate_scale(VerifiedTokens::get_coin_metadata_tier(&metadata),false) as u256),
                        false,
                        5
                   );

                   // let margin_interest = current_raw_borrow * (utilization * (VerifiedTokens::apr_increase(VerifiedTokens::get_coin_metadata_tier(&metadata)) as u256))/ (VerifiedTokens::get_coin_metadata_denom(&metadata)) / 100;

                    total_dep = total_dep + (dep_usd * (VerifiedTokens::lend_ratio(VerifiedTokens::get_coin_metadata_tier(&metadata)) as u256)) / 100;
                    total_bor = total_bor + bor_usd;
                    total_rew = total_rew + reward_usd;
                    total_int = total_int + interest_usd;
                    total_expected_interest = total_expected_interest + margin_interest;
                    raw_borrow = raw_borrow + current_raw_borrow;

                    y = y + 1;
                };

                b = b + 1;
            };
            i = i + 1;
        };

        (total_dep, total_bor, raw_borrow, total_rew, total_int, total_expected_interest)
    }

    #[view]
    public fun get_all_user_vaults(addr: address): vector<UserVaults>
    acquires TokenHoldings {
        let tokens_holdings = borrow_global_mut<TokenHoldings>(@dev);
        let uv_vect = vector::empty<UserVaults>();

        // get all vault provider types
        let vaults = VaultTypes::return_all_vault_provider_types();
        let a = vector::length(&vaults);
        let b = 0;

        // loop through each vault provider
        while (b < a) {
            let vault = vector::borrow(&vaults, b);
            let vault_str = *vault;

            let tokens = vector::empty<String>();

            // --- fetch user's tokens if any ---
            if (table::contains(&tokens_holdings.holdings, addr)) {
                let user_holdings_ref = table::borrow(&tokens_holdings.holdings, addr);

                if (table::contains(user_holdings_ref, utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraCoinTypesV5::Market"))) {
                    let holdings_ref = table::borrow(user_holdings_ref, utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraCoinTypesV5::Market"));

                    if (table::contains(holdings_ref, vault_str)) {
                        let balances = table::borrow(holdings_ref, vault_str);
                        let len = vector::length(balances);
                        let  j = 0;
                        while (j < len) {
                            let holding = vector::borrow(balances, j);
                            vector::push_back(&mut tokens, holding.token);
                            j = j + 1;
                        };
                    };
                };
            };

            // --- build vault-specific balance list ---
            let num_tokens = vector::length(&tokens);
            let y = 0;
            let v_vect = vector::empty<Balance>();

            while (y < num_tokens) {
                let token_id = *vector::borrow(&tokens, y);

                // provide vault + feature params explicitly
                let uv_ref = find_balance(tokens_holdings, addr, token_id, vault_str, utf8(b"0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0::QiaraCoinTypesV5::Market"));
                vector::push_back(&mut v_vect, *uv_ref);

                y = y + 1;
            };

            let user_vault = UserVaults { provider: vault_str, vaults: v_vect };
            vector::push_back(&mut uv_vect, user_vault);

            b = b + 1;
        };

        uv_vect
    }



    #[view]
    public fun get_user_balance<T, X, Y>(addr: address): Balance acquires TokenHoldings {
        return *find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>())
    }

    #[view]
    public fun get_user_raw_balance<T, X, Y>(addr: address): (String, u64, u64, u128, u128, u64) acquires TokenHoldings {
        let balance  = *find_balance(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>(), type_info::type_name<X>(), type_info::type_name<Y>());
        return (balance.token, balance.deposited, balance.borrowed, balance.reward_index_snapshot, balance.interest_index_snapshot, balance.last_update)
    }

    #[view]
    public fun get_user_balances<X, Y>(addr: address): vector<Balance> acquires TokenHoldings {
        let th = borrow_global<TokenHoldings>(@dev);
        let inner = table::borrow(&th.holdings, addr);
        let inner2 = table::borrow(inner, type_info::type_name<X>());
        *table::borrow(inner2, type_info::type_name<Y>())
    }

    #[view]
    public fun get_user_credit<T>(addr: address): Credit acquires TokenHoldings {
        return *find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>())
    }

    #[view]
    public fun get_user_raw_credit<T>(addr: address): (String, u64, u64, u64, u64, u64) acquires TokenHoldings {
        let credit  = *find_credit(borrow_global_mut<TokenHoldings>(@dev),addr, type_info::type_name<T>());
        return (credit.token, credit.deposited, credit.borrowed, credit.rewards, credit.interest, credit.leverage)
    }


// === MUT RETURNS === //

fun find_credit(token_table: &mut TokenHoldings, addr: address, token: String): &mut Credit {
    // Use scoped blocks to end borrows early when needed
    {
        if (!table::contains(&token_table.credits, addr)) {
            table::add(&mut token_table.credits, addr, table::new<String, Credit>());
        };
    };

    let user_credit_table = table::borrow_mut(&mut token_table.credits, addr);

    if (!table::contains(user_credit_table, token)) {
        table::add(
            user_credit_table,
            token,
            Credit {
                token,
                deposited: 0,
                borrowed: 0,
                rewards: 0,
                interest: 0,
                leverage: 1,
            },
        );
    };

    table::borrow_mut(user_credit_table, token)
}

fun find_balance(
    feature_table: &mut TokenHoldings,
    addr: address,
    token: String,
    vault: String,
    feature: String
): &mut Balance {
    {
        if (!table::contains(&feature_table.holdings, addr)) {
            table::add(
                &mut feature_table.holdings,
                addr,
                table::new<String, table::Table<String, vector<Balance>>>(),
            );
        };
    };

    let user_holdings = table::borrow_mut(&mut feature_table.holdings, addr);

    {
        if (!table::contains(user_holdings, feature)) {
            table::add(
                user_holdings,
                feature,
                table::new<String, vector<Balance>>(),
            );
        };
    };

    let vault_table = table::borrow_mut(user_holdings, feature);

    {
        if (!table::contains(vault_table, vault)) {
            table::add(vault_table, vault, vector::empty<Balance>());
        };
    };

    let holdings = table::borrow_mut(vault_table, vault);
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
        token,
        deposited: 0,
        borrowed: 0,
        reward_index_snapshot: 0,
        interest_index_snapshot: 0,
        last_update: 0,
    };
    vector::push_back(holdings, new_balance);

    let idx = vector::length(holdings) - 1;
    vector::borrow_mut(holdings, idx)
}

fun find_vault(vault_table: &mut Vaults, vault: String): &mut Vault {
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
}


// === HELPERS === //
    public fun is_user_registered(address: address): bool {
        if (!exists<TokenHoldings>(address)) {
            return false
        };

        if (!exists<VaultRegistry>(address)) {
            return false
        };

        if (!exists<FeaturesRegistry>(address)) {
            return false
        };
        return true
    }

    public fun get_utilization_ratio(addr: address): u256 acquires TokenHoldings{
        assert_user_registered(addr);
        let (depoUSD, borrowUSD, _, _, _, _) = get_user_total_usd(addr);
        if (depoUSD == 0) {
            0
        } else {
            ((borrowUSD * 100) / depoUSD as u256)
        }
    }

    public fun assert_user_registered(address: address) {
        assert!(!exists<TokenHoldings>(address), ERROR_USER_NOT_REGISTERED);
        assert!(!exists<FeaturesRegistry>(address), ERROR_USER_NOT_REGISTERED);
        assert!(!exists<VaultRegistry>(address), ERROR_USER_NOT_REGISTERED);
    }
}
