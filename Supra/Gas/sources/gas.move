module dev::QiaraGasV2{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table;
    use std::timestamp;
    use std::bcs;
    use supra_framework::event;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::math128 ::{Self as math128};

    use dev::QiaraMarginV16::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRIV16::{Self as RI};
    use dev::QiaraEventV15::{Self as Event};
    use dev::QiaraTokensMetadataV12::{Self as TokensMetadata, VMetadata};

    use dev::QiaraSharedV6::{Self as Shared};

    use dev::QiaraTokenTypesV11::{Self as TokensTypes};

    use dev::QiaraMathV1::{Self as QiaraMath};
    use dev::QiaraNonceV5::{Self as Nonce, Access as NonceAccess};

    use dev::QiaraVaultsV15::{Self as Market, Access as MarketAccess};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_MARKET_ALREADY_EXISTS: u64 = 2;
    const ERROR_LEVERAGE_TOO_LOW: u64 = 3;
    const ERROR_SENDER_DOESNT_MATCH_SIGNER: u64 = 4;
    const ERROR_UNKNOWN_PERP_TYPE: u64 = 5;

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

    struct Gas has copy, key, store {
        avg_leverage: u64,
        usd_deposits: u256,
        usd_withdrawals: u256,
        usd_borrows: u256,
        gas: u256,
        last_update: u64,
    }


/// === INIT ===
    fun init_module(admin: &signer){

        if (!exists<Gas>(@dev)) {
            move_to(admin, Gas { avg_leverage: 0, usd_deposits: 0, usd_withdrawals: 0, usd_borrows: 0, gas: 0, last_update: timestamp::now_seconds() });
        };
    }

    public fun add_leverage(leverage: u64) acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.avg_leverage = gas.avg_leverage + leverage;
    }


    public fun add_deposit(deposit: u256) acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_deposits = gas.usd_deposits + deposit;
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, deposit, 0);
        gas.gas = gas_rate;
    }


    public fun add_withdraw(withdraw: u256) acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_withdrawals = gas.usd_withdrawals + withdraw;
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, withdraw);
        gas.gas = gas_rate;
    }


    public fun add_borrow(borrow: u256) acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_borrows = gas.usd_borrows + borrow;
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, 0);
        gas.gas = gas_rate;
    }




    //supra move tool view --function-id 0xc536f11396d0510d90b021cbae973ab1f71155e8ff32c9d544bfb48212b11ac9::QiaraGasV1::calculateFunding --args u256:50 u256:1250000 u256:2500000 u256:1250000 u256:1522143811 u256:408101064 u256:784666762 u256:3481215007  u256:275
    #[view]
    public fun calculateFunding(skewer: u256, avg_leverage: u256, base: u256,withdrawal_weight: u256, prev_deposits: u256, deposits: u256, prev_withdrawals: u256, withdrawals: u256, last_update_sec: u256,): (u256,u256,u256,u256,u256,u256) {
        // let base = 2_500_000 2_500_000
        // let avg_leverage = 1_250_000 1_250_000 1_250_000
        // let skewer = 500 (0,000050)
        // let withdrawal_weight = 1_250_000
        //7_760_369633536
        //1_940_092.40838
        // 7_760_369 * 2_500_000
        let e18 = 1000000000000000000;
        let e6 = 1_000_000;
        let previous_deposit_impact = prev_deposits-((prev_deposits*skewer*last_update_sec)/1_000_000);
        let previous_withdrawal_impact = prev_withdrawals-((prev_withdrawals*skewer*last_update_sec)/1_000_000);

        let new_deposits = deposits + previous_deposit_impact;
        let new_withdrawals = withdrawals + previous_withdrawal_impact;

        let ratio = ((new_withdrawals*withdrawal_weight))/new_deposits;

        let total_fee = (base * ((ratio*ratio)/e6)/e6) + avg_leverage + base;
        return (total_fee, previous_deposit_impact, previous_withdrawal_impact, new_deposits, new_withdrawals, ((ratio*ratio)/e6))
    }

// 1. Remove "acquires Gas" here. You are passing the reference in.
    public fun calculateGas(gas_ref: &mut Gas, deposit: u256, withdrawal: u256): (u256,u256,u256,u256,u256,u256) {
        let base = 2_500_000;
        let skewer = 50;
        let withdrawal_weight = 1_250_000;
        let e6 = 1_000_000;

        let last_update_sec = ((timestamp::now_seconds() - gas_ref.last_update) as u256);

        // Standard decay logic
        let previous_deposit_impact = if (gas_ref.usd_deposits > 0) {
            let decay = (gas_ref.usd_deposits * skewer * last_update_sec) / e6;
            if (gas_ref.usd_deposits > decay) gas_ref.usd_deposits - decay else 0
        } else { 0 };

        let previous_withdrawal_impact = if (gas_ref.usd_withdrawals > 0) {
            let decay = (gas_ref.usd_withdrawals * skewer * last_update_sec) / e6;
            if (gas_ref.usd_withdrawals > decay) gas_ref.usd_withdrawals - decay else 0
        } else { 0 };

        let new_deposits = deposit + previous_deposit_impact;
        let new_withdrawals = withdrawal + previous_withdrawal_impact;

        let ratio = if (new_deposits > 0) {
            (new_withdrawals * withdrawal_weight) / new_deposits
        } else {
            0
        };

        let total_fee = (base * ((ratio * ratio) / e6) / e6) + (gas_ref.avg_leverage as u256) + base;
        
        return (total_fee, previous_deposit_impact, previous_withdrawal_impact, new_deposits, new_withdrawals, ((ratio * ratio) / e6))
    }

       #[view]
       public fun return_gas(): Gas acquires Gas{
           return *borrow_global<Gas>(@dev)
       }

}
