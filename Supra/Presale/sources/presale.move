module dev::QiaraPresaleVaultV3 {
    use std::signer;
    use supra_framework::fungible_asset;
    use supra_framework::fungible_asset::{FungibleAsset, FungibleStore};
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};
    use supra_framework::coin;
    use supra_framework::supra_coin::SupraCoin;

    use dev::QiaraTestV27 as Qiara;

    const E_INSUFFICIENT_VAULT_BALANCE: u64 = 100;

    struct QiaraVault has key, store {
        balance: Object<FungibleStore>, // qiara coin reserve
        bought: u64,
    }

    // supra coin "reserve"
    struct SupraVault has key {
        balance: coin::Coin<SupraCoin>,
    }

    fun init_module(admin: &signer) {
        let asset = Qiara::get_metadata();

        let constructor_ref = &object::create_named_object(admin, b"X1");

        let vault_store = fungible_asset::create_store(constructor_ref, asset);

        if (!exists<QiaraVault>(@dev)) {
            move_to(admin, QiaraVault { balance: vault_store, bought: 0});
        };
        if (!exists<SupraVault>(@dev)) {
            move_to(admin, SupraVault { balance: coin::zero<SupraCoin>() });
        };
    }


    public entry fun add_liquidity(sender: &signer, amount: u64) acquires QiaraVault {
        let qiara_vault = borrow_global_mut<QiaraVault>(@dev);  
        Qiara::deposit_to_store(sender, qiara_vault.balance, amount);
    }

    public entry fun remove_liquidity(sender: &signer) acquires QiaraVault, SupraVault {
        let qiara_vault = borrow_global_mut<QiaraVault>(@dev);
        let supra_vault = borrow_global_mut<SupraVault>(@dev);

        let supra_liquidity = coin::extract_all<SupraCoin>(&mut supra_vault.balance);
        coin::deposit(signer::address_of(sender), supra_liquidity);

        let qiara_liquidity = fungible_asset::balance(qiara_vault.balance);
        Qiara::withdraw_from_store(sender, qiara_vault.balance, qiara_liquidity);
    }

    public entry fun buy(sender: &signer, coin_amount: u64) acquires QiaraVault, SupraVault {
        let qiara_vault = borrow_global_mut<QiaraVault>(@dev);

        // Withdraw SupraCoin from user
        let payment = coin::withdraw<SupraCoin>(sender, coin_amount);
        let vault = borrow_global_mut<SupraVault>(@dev);
        coin::merge(&mut vault.balance, payment);

        // Current Qiara price = 1.0 + growth curve
        let steps = qiara_vault.bought / (1000*1_000_000);
        let price = 1_000; // micro-units (1 Supra = 1 Qiara initially)
        let i = 0;
        while (i < steps) {
            price = price * 101 / 100; // +1% every 1000 Qiara sold
            i = i + 1;
        };
        //1_00_000_000 = 1 supra
        // Normalize decimals: Supra=12, Qiara=6
        let dy = coin_amount * 1_000_000 / ( 1_000_000);

        // Cap at available Qiara
        let dy = if (dy > fungible_asset::balance(qiara_vault.balance)) { fungible_asset::balance(qiara_vault.balance) } else { dy };

        // Transfer Qiara to user
        Qiara::withdraw_from_store(sender, qiara_vault.balance, dy);
        qiara_vault.bought = qiara_vault.bought + dy;
    }





    #[view]
    public fun calculate_price(): u64 acquires QiaraVault {
        let qiara_vault = borrow_global<QiaraVault>(@dev);

        let initial_price: u64 = 1_000_000; // 1 Supra = 1 Qiara
        let scaling_factor: u64 = 10_000;   // adjust for how fast price rises

        // Price increases linearly with total Qiara bought
        let price: u64 = initial_price + (scaling_factor * qiara_vault.bought);

        price
    }


    #[view]
    public fun get_qiara_liquidity(): u64 acquires QiaraVault{
        let qiara_vault = borrow_global<QiaraVault>(@dev);
        fungible_asset::balance(qiara_vault.balance)
    }

    #[view]
    public fun get_supra_liquidity(): u64 acquires SupraVault{
        let supra_vault = borrow_global<SupraVault>(@dev);
        coin::value(&supra_vault.balance)
    }
}
