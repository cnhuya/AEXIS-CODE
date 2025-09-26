module dev::QiaraTokenStorageV18{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::option::{Self as option, Option};
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_framework::coin;
    use dev::AexisVaultFactoryV18::{Self as Factory, Tier, CoinData, Metadata};
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NO_USER_BALANCE_REGISTERED: u64 = 2;


    struct Holdings has key {
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
    }

    struct TokenHoldings has key {
        holdings: table::Table<address, table::Table<String, Holdings>,
    }

    struct TokenListRegistry has key {
        list: table::Table<address, String>,
    }


    struct Access has store, key, drop {}
    struct TokensPermission has key, drop { }

    public fun give_access(admin: &signer): Access{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_tokens_permission(access: &Access): TokensPermission{
        TokensPermission {}
    }

    /// ========== INIT ==========
    fun init_module(admin: &signer) acquires Tiers{
        let deploy_addr = signer::address_of(admin);

        if (!exists<TokenHoldings>(deploy_addr)) {
            move_to(admin, TokenHoldings { holdings: table::new<address, table::Table<address, Holdings>>()});
        };

        if (!exists<TokenListRegistry>(deploy_addr)) {
            move_to(admin, TokenListRegistry { list: table::new<address,String>()});
        };

    }


    fun find_holding(address: address, token: String, isPositive: bool, ): &mut Holdings acquires TokenHoldings, TokenListRegistry{
        let tokens_holdings = borrow_global_mut<TokenHoldings>(ADMIN);
        let tokens_registry = borrow_global_mut<TokenListRegistry>(ADMIN);

        if (!table::contains(&tokens_registry.list, to)) {
            table::add(&mut tokens_registry.list, to, token);
        };
        
        let current_table;
        if(isPositive = true){
            if (!table::contains(&tokens_holdings.holdings, to)) {
                table::add(&mut tokens_holdings.holdings, to, token);
            }
            current_table = table::borrow_mut(&mut tokens_holdings.holdings, to);
            if(isPositive = true){
                return token_amount = table::borrow_mut(&mut current_table.deposited, token)
            } else {
                return token_amount = table::borrow_mut(&mut current_table.borrowed, token)
            };
        };

    }
    public fun accrue_rewards<T>(address: address, value: u64, cap: TokensPermission) acquires TokenHoldings {
        let type_str = type_info::type_name<T>();

        let holdings = find_holding(address, type_str, true);
        holdings.rewards = holdings.rewards + value;

    }

    public fun accrue_interest<T>(address: address, value: u64, cap: TokensPermission) acquires TokenHoldings {
        let type_str = type_info::type_name<T>();

        let holdings = find_holding(address, type_str, true);
        holdings.interest = holdings.interest + value;

    }

    public fun add_balance(admin: &signer, to: address, token: String, value: u64, isDeposit: bool, cap: TokensPermission) acquires TokenHoldings, TokenListRegistry{
        let holdings = find_holding(to, token, isPositive);
        if(isDeposit){
            holdings.deposited = holdings.deposited + value;
        } else{
            holdings.borrowed = holdings.borrowed + value;
        }
    }


    public fun remove_balance(admin: &signer, to: address, token: String, value: u64, isPositive: bool, cap: TokensPermission) acquires TokenHoldings, TokenListRegistry{
        let holdings = find_holding(to, token, isPositive);
        if(isDeposit){
            if(value > holdings.deposited){
                holdings.deposited = 0
            } else {
                holdings.deposited = holdings.deposited - value;
            }
        } else{
            if(value > holdings.deposited){
                holdings.borrowed = 0
            } else {
                holdings.borrowed = holdings.borrowed - value;
            }
        }
    }


    #[view]
    public fun get_user_position_usd<T,X>(addr: address): (u256, u256, u256, u256) acquires TokenHoldings, TokenListRegistry  {
        let tokens_holdings = borrow_global_mut<TokenHoldings>(ADMIN);
        let tokens_registry = borrow_global_mut<TokenListRegistry>(ADMIN);

        // get coin decimals
        let coin_decimals = coin::decimals<T>();

        // lookup oracle metadata
        let metadata = Factory::get_coin_metadata_by_res(&type_info::type_name<T>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));
        
        // normalize amount * price / 10^coin_decimals
        let denom = pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

        let dep_usd = ((((uv.deposited as u256) * (price as u256)) / denom)*(Factory::lend_ratio(Factory::get_coin_metadata_tier(&metadata)) as u256))/100;
        let bor_usd = ((uv.borrowed as u256)  * (price as u256)) / denom;
        let reward_usd = ((uv.rewards as u256)  * (price as u256)) / denom;
        let interest_usd = ((uv.interest as u256)  * (price as u256)) / denom;

        (dep_usd, bor_usd, reward_usd ,interest_usd)
    }

    #[view]
    public fun get_user_total_usd(addr: address): (u256, u256, u256, u256) acquires UserVaultRegistry, UserVault{
        let user_vault = borrow_global_mut<UserVault>(addr);
        let user_vault_registry = borrow_global_mut<UserVaultRegistry>(addr);

        let total_dep = 0u256;
        let total_bor = 0u256;
        let total_rew = 0u256;
        let total_int = 0u256;

        let n = vector::length(&user_vault_registry.coins);
        let i = 0;
        while (i < n) {
            let key_vault_type = vector::borrow(&user_vault_registry.coins, i);
            let provider_list = VaultProviders::return_all_vault_provider_types();
            let x = vector::length(&user_vault_registry.coins);
            let y = 0;
            while (y < x) {
                let provider = vector::borrow(&provider_list, x);
                let uv = find_user_deposited(user_vault, *key_vault_type, *provider);            
                let metadata = Factory::get_coin_metadata_by_res(&uv.resource);
                let (price, price_decimals, _, _) = supra_oracle_storage::get_price(Factory::get_coin_metadata_oracle(&metadata));


                // denominator = 10^(coin_decimals + price_decimals)
                let denom = pow10_u256(Factory::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

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

                x = x + 1;
            };

            i = i + 1;
        };
        (total_dep, total_bor, total_rew, total_int)
    }

}
