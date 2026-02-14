module 0x0::USDC {

    use sui::coin::{Self, TreasuryCap, Coin, CoinMetadata};

    public struct USDC has drop {}


    fun init(witness: USDC, ctx: &mut TxContext) {
            let (mut treasury, metadata) = coin::create_currency(
                    witness,
                    6,
                    b"Qiara Test USDC",
                    b"QTUSDC",
                    b"",
                    option::none(),
                    ctx,
            );
            mint(&mut treasury, 999999999999, ctx.sender(), ctx);
            transfer::public_freeze_object(metadata);
            transfer::public_transfer(treasury, ctx.sender())
    }

    public fun mint(treasury_cap: &mut TreasuryCap<USDC>,amount: u64,recipient: address,ctx: &mut TxContext,) {
            let coin = coin::mint(treasury_cap, amount, ctx);
            transfer::public_transfer(coin, recipient)
    }
}