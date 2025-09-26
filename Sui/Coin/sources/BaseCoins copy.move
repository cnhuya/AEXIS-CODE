module 0x0::SUIBITCOIN {

    use sui::coin::{Self, TreasuryCap, Coin, CoinMetadata};

    public struct SUIBITCOIN has drop {}


    fun init(witness: SUIBITCOIN, ctx: &mut TxContext) {
            let (treasury, metadata) = coin::create_currency(
                    witness,
                    6,
                    b"Sui Bitcoin",
                    b"SuiBTC",
                    b"",
                    option::none(),
                    ctx,
            );
            transfer::public_freeze_object(metadata);
            transfer::public_transfer(treasury, ctx.sender())
    }

    public fun mint(treasury_cap: &mut TreasuryCap<SUIBITCOIN>,amount: u64,recipient: address,ctx: &mut TxContext,) {
            let coin = coin::mint(treasury_cap, amount, ctx);
            transfer::public_transfer(coin, recipient)
    }
}