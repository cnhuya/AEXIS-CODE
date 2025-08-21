module dev::aexisVaultV1 {
    use std::signer;
    use std::string::{String, utf8};
    use std::timestamp;
    use supra_framework::coin;
    use supra_framework::supra_coin::{Self, SupraCoin};
    use supra_framework::event;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 2;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 3;
    const ERROR_USER_VAULT_NOT_INITIALIZED: u64 = 4;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 5;
    const ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION: u64 = 6;

    const ADMIN: address = @dev;

    const SECONDS_IN_YEAR: u64 = 31_536_000; // 365 days
    const DEFAULT_SUPPLY_APY_BPS: u64 = 5000000; // 50000% APY
    const DEFAULT_BORROW_APY_BPS: u64 = 10000000; // 100000% APY

    const MAX_COLLATERAL_RATIO: u64 = 80; // Safe borrowing limit (%)
    const LIQUIDATION_THRESHOLD: u64 = 85; // Liquidation trigger (%)
    const LIQUIDATION_BONUS_BPS: u64 = 500; // 5% bonus to liquidator

    struct UserVault has key, copy, drop {
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
        last_update: u64,
    }

    struct GlobalVault has key {
        total_deposited: u64,
        balance: coin::Coin<SupraCoin>,
    }

    struct Vault has copy, drop {
        total_deposited: u64,
        balance: u64,
        borrowed: u64,
    }

    struct Access has store, key, drop {}

    #[event]
    struct DepositEvent has copy, drop, store {
        amount: u64,
        from: address,
    }

    #[event]
    struct WithdrawEvent has copy, drop, store {
        amount: u64,
        to: address,
    }

    #[event]
    struct BorrowEvent has copy, drop, store {
        amount: u64,
        to: address,
    }

    #[event]
    struct ClaimRewardsEvent has copy, drop, store {
        amount: u64,
        to: address,
    }

    #[event]
    struct LiquidationEvent has copy, drop, store {
        borrower: address,
        liquidator: address,
        repaid: u64,
        collateral_seized: u64,
    }

    fun get_admin(): address {
        ADMIN
    }

    public entry fun init_vault(admin: &signer) {
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        if (!exists<GlobalVault>(ADMIN)) {
            move_to(admin, GlobalVault {
                total_deposited: 0,
                balance: coin::zero<SupraCoin>(),
            });
        }
    }

    public fun get_vault_access(admin: &signer): Access {
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        Access {}
    }

    public entry fun deposit(user: &signer, amount: u64) acquires GlobalVault, UserVault {
        assert!(exists<GlobalVault>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault>(ADMIN);

        if (!exists<UserVault>(signer::address_of(user))) {
            move_to(user, UserVault { deposited: 0, borrowed: 0, rewards: 0,  interest: 0, last_update: timestamp::now_seconds(), });
        };
        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));

        accrue(user_vault);

        let coins = coin::withdraw(user, amount);
        coin::merge(&mut vault.balance, coins);

        vault.total_deposited = vault.total_deposited + amount;
        user_vault.deposited = user_vault.deposited + amount;

        event::emit(DepositEvent { amount, from: signer::address_of(user) });
    }

    public entry fun withdraw(user: &signer, amount: u64) acquires GlobalVault, UserVault {
        assert!(exists<GlobalVault>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault>(ADMIN);

        assert!(exists<UserVault>(signer::address_of(user)), ERROR_USER_VAULT_NOT_INITIALIZED);
        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));

        accrue(user_vault);

        assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        vault.total_deposited = vault.total_deposited - amount;
        user_vault.deposited = user_vault.deposited - amount;

        event::emit(WithdrawEvent { amount, to: signer::address_of(user) });
    }

    public entry fun borrow(user: &signer, amount: u64) acquires GlobalVault, UserVault {
        assert!(exists<GlobalVault>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<GlobalVault>(ADMIN);

        assert!(exists<UserVault>(signer::address_of(user)), ERROR_USER_VAULT_NOT_INITIALIZED);
        let user_vault = borrow_global_mut<UserVault>(signer::address_of(user));

        accrue(user_vault);

        assert!(user_vault.deposited >= amount, ERROR_INSUFFICIENT_BALANCE);
        assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);

        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(signer::address_of(user), coins);

        user_vault.borrowed = user_vault.borrowed + amount;

        event::emit(BorrowEvent { amount, to: signer::address_of(user) });
    }

    public entry fun claim_rewards(user: &signer) acquires GlobalVault, UserVault {
        let addr = signer::address_of(user);
        assert!(exists<UserVault>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        let vault = borrow_global_mut<UserVault>(addr);

        accrue(vault);

        let reward_amount = vault.rewards;
        assert!(reward_amount > 0, ERROR_INSUFFICIENT_BALANCE);

        vault.rewards = 0;

        let global_vault = borrow_global_mut<GlobalVault>(ADMIN);
        assert!(coin::value(&global_vault.balance) >= reward_amount, ERROR_NOT_ENOUGH_LIQUIDITY);
        let coins = coin::extract(&mut global_vault.balance, reward_amount);
        coin::deposit(addr, coins);

        event::emit(ClaimRewardsEvent { amount: reward_amount, to: signer::address_of(user) });
    }

    public entry fun liquidate(
        liquidator: &signer,
        borrower_addr: address,
        repay_amount: u64
    ) acquires GlobalVault, UserVault {
        assert!(exists<UserVault>(borrower_addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        assert!(exists<GlobalVault>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);

        let borrower_vault = borrow_global_mut<UserVault>(borrower_addr);
        accrue(borrower_vault);

        let collateral_ratio = (borrower_vault.borrowed * 100) / borrower_vault.deposited;
        assert!(collateral_ratio >= LIQUIDATION_THRESHOLD, ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION);

        let actual_repay = if repay_amount > borrower_vault.borrowed {
            borrower_vault.borrowed
        } else {
            repay_amount
        };

        let repayment = coin::withdraw(liquidator, actual_repay);
        let global_vault = borrow_global_mut<GlobalVault>(ADMIN);
        coin::merge(&mut global_vault.balance, repayment);

        borrower_vault.borrowed = borrower_vault.borrowed - actual_repay;

        let bonus = (actual_repay * LIQUIDATION_BONUS_BPS) / 10000;
        let collateral_to_liquidator = actual_repay + bonus;

        assert!(borrower_vault.deposited >= collateral_to_liquidator, ERROR_INSUFFICIENT_BALANCE);
        borrower_vault.deposited = borrower_vault.deposited - collateral_to_liquidator;

        let collateral_coins = coin::extract(&mut global_vault.balance, collateral_to_liquidator);
        coin::deposit(signer::address_of(liquidator), collateral_coins);

        event::emit(LiquidationEvent {
            borrower: borrower_addr,
            liquidator: signer::address_of(liquidator),
            repaid: actual_repay,
            collateral_seized: collateral_to_liquidator,
        });
    }

    #[view]
    public fun get_vault(): Vault acquires GlobalVault {
        assert!(exists<GlobalVault>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault>(ADMIN);
        let balance = coin::value(&vault.balance);
        Vault {total_deposited: vault.total_deposited,balance,borrowed: vault.total_deposited - balance}
    }

    #[view]
    public fun get_vault_balance(): u64 acquires GlobalVault {
        assert!(exists<GlobalVault>(ADMIN), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault>(ADMIN);
        coin::value(&vault.balance)
    }

    #[view]
    public fun get_user_vault(addr: address): UserVault acquires UserVault {
        assert!(exists<UserVault>(addr), ERROR_USER_VAULT_NOT_INITIALIZED);
        *borrow_global<UserVault>(addr)
    }

    #[view]
    public fun get_utilization_ratio(): u64 acquires GlobalVault {
        let vault = get_vault();
        if (vault.total_deposited == 0) {
            0
        } else {
            (vault.borrowed * 100) / vault.total_deposited
        }
    }

    #[view]
    public fun get_user_collatelar_ratio(address: address): u64 acquires UserVault {
        let vault = get_user_vault(address);
        (vault.borrowed * 100) / vault.deposited
    }

    #[view]
    public fun get_apy(): u64 acquires GlobalVault {
        let utilization = get_utilization_ratio();
        utilization / 2
    }

    fun accrue(user_vault: &mut UserVault) {
        let current_timestamp = timestamp::now_seconds();
        let time_diff = current_timestamp - user_vault.last_update;
        if (time_diff == 0) return;

        let reward = (user_vault.deposited * DEFAULT_SUPPLY_APY_BPS * time_diff)
            / (SECONDS_IN_YEAR * 10000);
        user_vault.rewards = user_vault.rewards + reward;

        let interest = (user_vault.borrowed * DEFAULT_BORROW_APY_BPS * time_diff)
            / (SECONDS_IN_YEAR * 10000);
        user_vault.interest = user_vault.interest + interest;

        user_vault.last_update = current_timestamp;
    }
}
