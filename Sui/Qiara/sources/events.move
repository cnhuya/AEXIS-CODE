module Qiara::QiaraEventsV1 {
    use std::vector;
    use sui::address;
    use std::string::{Self, String};
    use sui::event;
// --- Events ---

    public struct Deposit has copy, drop {
        user: address,
        token_type: String,
        amount: u64,
        provider: String
    }

    public struct WithdrawGrant has copy, drop {
        user: address,
        token_type: String,
        amount: u64,
        provider: String,
        nullifier: u256
    }

    public struct Withdrawal has copy, drop {
        user: address,
        token_type: String,
        amount: u64,
        provider: String
    }

    public fun emit_deposit_event(user: address, token_type: String, amount: u64, provider: String) {
        event::emit(Deposit {user: user,token_type: token_type,amount: amount,provider: provider,});
    }
    public fun emit_withdraw_event(user: address, token_type: String, amount: u64, provider: String) {
        event::emit(Withdrawal {user: user,token_type: token_type,amount: amount,provider: provider,});
    }
    public fun emit_withdraw_grant_event(user: address, token_type: String, amount: u64, provider: String, nullifier: u256) {
        event::emit(WithdrawGrant {user: user,token_type: token_type,amount: amount,provider: provider, nullifier: nullifier,});
    }

}