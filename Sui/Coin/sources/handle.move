module 0x0::VAULT_HANDLE {

    use sui::coin::{Self, TreasuryCap, Coin, CoinMetadata};

    public struct VAULT_HANDLE has drop {}

    fun init(witness: VAULT_HANDLE, ctx: &mut TxContext) {

            transfer::public_transfer(vault, ctx.sender())
    }

    public fun mint(treasury_cap: &mut TreasuryCap<SUIBITCOIN>,amount: u64,recipient: address,ctx: &mut TxContext,) {
            let coin = coin::mint(treasury_cap, amount, ctx);
            transfer::public_transfer(coin, recipient)
    }
}