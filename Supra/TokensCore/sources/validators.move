module dev::QiaraTokensValidatorsV36 {
    use std::signer;
    use std::string::{Self as string, String, utf8};
    use std::table::{Self, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};


    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_REWARD_TOO_SMALL: u64 = 1;
    const ERROR_INVALID_VALIDATOR: u64 = 2;
    const ERROR_TOKEN_NOT_YET_REWARDED: u64 = 3;
    // === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
    
    // === STRUCTS === //
    struct Permissions has key {
    }

    struct ValidatorRewards has key {
        balances: Table<address, Table<String, Map<String, u256>>>
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        if (!exists<ValidatorRewards>(@dev)) {
            move_to(admin, ValidatorRewards { balances: table::new<address,Table<String, Map<String, u256>>>() });
        };
    }


   public fun ensure_and_accrue_validator_reward_balance(validator: address, token: String, chain: String, amount: u256, perm: Permission) acquires ValidatorRewards {
        let ref = borrow_global_mut<ValidatorRewards>(@dev);
        // Ensure validator entry exists
        if (!table::contains(&ref.balances, validator)) {
            table::add(&mut ref.balances, validator, table::new<String, Map<String, u256>>());
        };
        
        let validator_balances = table::borrow_mut(&mut ref.balances, validator);
        
        // Ensure token entry exists
        if (!table::contains(validator_balances, token)) {
            table::add(validator_balances, token, map::new<String, u256>());
        };
        
        let token_balances = table::borrow_mut(validator_balances, token);
        
        // Ensure chain entry exists and return mutable reference
        if (!map::contains_key(token_balances, &chain)) {
            map::add(token_balances, chain, amount);
            return
        };
        
        let x = map::borrow_mut(token_balances, &chain);
        map::upsert(token_balances, chain, *x+amount);
    }

    public fun ensure_decimal_safety(amount: u256){
        assert!(amount > 1_000_000*1_000_000, ERROR_REWARD_TOO_SMALL) // token_decimals * storage contant scailing
    }

    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------
    #[view]
    public fun return_validator_rewards(validator: address, token: String): Map<String, u256> acquires ValidatorRewards {
         let rewards = borrow_global<ValidatorRewards>(@dev);

        // Ensure validator entry exists
        if (!table::contains(&rewards.balances, validator)) {
            abort ERROR_INVALID_VALIDATOR
        };

        let validator_balances = table::borrow(&rewards.balances, validator);
        // Ensure token entry exists
        if (!table::contains(validator_balances, token)) {
            abort ERROR_TOKEN_NOT_YET_REWARDED
        };
        
        *table::borrow(validator_balances, token)
    }


}