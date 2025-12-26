module dev::QiaraVaultsV39 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::bcs;
    use supra_oracle::supra_oracle_storage;
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::dispatchable_fungible_asset;
    use supra_framework::primary_fungible_store;
    use supra_framework::object::{Self, Object};
    use supra_framework::event;

    use dev::QiaraTokensCoreV47::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensMetadataV47::{Self as TokensMetadata, VMetadata};
    use dev::QiaraTokensSharedV47::{Self as TokensShared};
    use dev::QiaraTokensRatesV47::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensOmnichainV47::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    
    use dev::QiaraMarginV56::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRIV56::{Self as RI};

   // use dev::QiaraFeeVaultV10::{Self as fee};

    use dev::QiaraTokenTypesV28::{Self as TokensTypes};
    use dev::QiaraChainTypesV28::{Self as ChainTypes};
    use dev::QiaraProviderTypesV28::{Self as ProviderTypes};

    use dev::QiaraMathV9::{Self as QiaraMath};

    use dev::QiaraStorageV35::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV35::{Self as capabilities, Access as CapabilitiesAccess};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_VAULT_NOT_INITIALIZED: u64 = 99;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 3;
    const ERROR_USER_VAULT_NOT_INITIALIZED: u64 = 4;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 5;
    const ERROR_NOT_ELIGIBLE_FOR_LIQUIDATION: u64 = 6;
    const ERROR_INVALID_COIN_TYPE: u64 = 6;
    const ERROR_BORROW_COLLATERAL_OVERFLOW: u64 = 7;
    const ERROR_INSUFFICIENT_COLLATERAL: u64 = 8;
    const ERROR_NO_PENDING_DEPOSITS_FOR_THIS_VAULT_PROVIDER: u64 = 9;
    const ERROR_NO_DEPOSITS_FOR_THIS_VAULT_PROVIDER: u64 = 10;
    const ERROR_CANT_LIQUIDATE_THIS_VAULT: u64 = 11;
    const ERROR_CANT_ACRUE_THIS_VAULT: u64 = 12;
    const ERROR_NO_VAULT_FOUND: u64 = 13;
    const ERROR_NO_VAULT_FOUND_FULL_CYCLE: u64 = 14;
    const ERROR_UNLOCK_BIGGER_THAN_LOCK: u64 = 15;
    const ERROR_NOT_ENOUGH_MARGIN: u64 = 16;
    const ERROR_INVALID_TOKEN: u64 = 17;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 18;
    const ERROR_PROVIDER_DOESNT_SUPPORT_THIS_TOKEN_ON_THIS_CHAIN: u64 = 19;


    const ERROR_A: u64 = 101;
    const ERROR_B: u64 = 102;
    const ERROR_C: u64 = 103;
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key, store, drop {
        margin: MarginAccess,
        tokens_rates: TokensRatesAccess,
        tokens_omnichain: TokensOmnichainAccess,
        tokens_core: TokensCoreAccess,
        storage: StorageAccess,
        capabilities: CapabilitiesAccess,
    }

// === STRUCTS === //
   
   // Maybe in the future remove this, and move total borrowed into global vault? idk tho how would it do because of the phantom type tag
    struct Vault has key, store, copy, drop{
        total_borrowed: u256,
        balance: Object<FungibleStore>,
    }

    struct FullVault has key, store, copy, drop{
        token: String,
        total_deposited: u256,
        total_borrowed: u256,
        utilization: u64,
        lend_rate: u64,
        borrow_rate: u64
    }

    struct GlobalVault has key {
        //  token, chain, provider
        balances: Table<String,Map<String, Map<String, Vault>>>,
    }

    struct VaultUSD has store, copy, drop {
        tier: u8,
        oracle_price: u128,
        oracle_decimals: u8,
        total_deposited: u256,
        balance: u64,
        borrowed: u256,
        utilization: u256,
        rewards: u256,
        interest: u256,
        fee: u256,
    }

    struct CompleteVault has key{
        vault: VaultUSD,
        coin: CoinMetadata,
        w_fee: u64,
        Metadata: VMetadata,
    }

// === EVENTS === //
    #[event]
    struct SwapVaultEvent has copy, drop, store {
        amountSwapped: u64,
        tokenFrom: String,
        chainFrom: String,
        providerFrom: String,
        amountReceived: u64,
        tokenTo: String,
        chainTo: String,
        providerTo: String,        
        time: u64
    }

    #[event]
    struct VaultEvent has copy, drop, store {
        validator: address,
        type: String,
        amount: u64,
        address: address,
        to: vector<u8>,
        token: String,
        chain: String,
        provider: String,
        time: u64
    }


// === FUNCTIONS === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { balances: table::new<String, Map<String, Map<String, Vault>>>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_omnichain: TokensOmnichain::give_access(admin), tokens_core: TokensCore::give_access(admin), storage:  storage::give_access(admin), capabilities:  capabilities::give_access(admin)});
        };
    //    init_all_vaults(admin);

    }

    public entry fun init_vault(admin: &signer, token: String, chain: String, provider: String) acquires GlobalVault {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
     
        ChainTypes::ensure_valid_chain_name(chain);
        
        find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
    }

    /// Deposit on behalf of `recipient`
    /// No need for recipient to have signed anything.
    public fun bridge_deposit(validator: &signer, sender: vector<u8>, shared_storage: vector<u8>, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        TokensOmnichain::change_UserTokenSupply(token, chain, sender, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 

        TokensRates::change_rates(token, chain, lend_rate, TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));
        // Yes it is intentional that recipient is first, because thats the shared storage. (in case i forget again)
        Margin::add_deposit(shared_storage, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        let fa = TokensCore::mint(token, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
        TokensCore::deposit(provider_vault.balance, fa, chain);

        accrue(provider_vault, shared_storage,sender, token, chain, provider);
        event::emit(VaultEvent {
            validator: signer::address_of(validator),
            type: utf8(b"Deposit"),
            amount: amount,
            sender: sender,
            to: shared_storage,
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
         });
    }

    // Recipient needs to be address here, in case permissioneless user wants to withdraw to existing Supra wallet.
    public fun bridge_withdraw(validator: &signer, sender: vector<u8>, shared_storage:vector<u8>, recipient: address, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        TokensRates::change_rates(token, chain, lend_rate, TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));
        // Yes it is intentional that recipient is first, because thats the shared storage. (in case i forget again)
        Margin::remove_deposit(shared_storage, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        let fa = TokensCore::withdraw(provider_vault.balance, amount, chain); 
        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(recipient,TokensCore::get_metadata(token)), fa, chain);

        accrue(provider_vault, shared_storage,sender, token, chain, provider);
        event::emit(VaultEvent {
            validator: signer::address_of(validator),
            type: utf8(b"Withdraw"),
            amount: amount,
            sender: sender,
            to: bcs::to_bytes(&recipient),
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
         });
    }

    // Recipient needs to be address here, in case permissioneless user wants to borrow to existing Supra wallet.
    public fun bridge_borrow(validator: &signer, sender: vector<u8>, shared_storage:vector<u8>, recipient: address, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        TokensOmnichain::change_UserTokenSupply(token, chain, sender, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 

        TokensRates::change_rates(token, chain, lend_rate, TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));
        // Yes it is intentional that recipient is first, because thats the shared storage. (in case i forget again)
        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        let fa = TokensCore::withdraw(provider_vault.balance, amount, chain);
        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(recipient,TokensCore::get_metadata(token)), fa, chain);

        Margin::add_borrow(shared_storage, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        provider_vault.total_borrowed = provider_vault.total_borrowed + (amount as u256);

        accrue(provider_vault, shared_storage,sender, token, chain, provider);

        event::emit(BridgeVaultEvent {
            validator: signer::address_of(validator),
            type: utf8(b"Borrow"),
            validator: signer::address_of(validator),
            amount: amount,
            sender: sender,
            to: bcs::to_bytes(&recipient),
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
         });
    }

    public fun bridge_repay(validator: &signer, sender: vector<u8>,  shared_storage:vector<u8>, token: String, chain: String, provider: String, amount: u64, lend_rate: u64, permission: Permission) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        let fa = TokensCore::mint(token, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
        TokensCore::deposit(provider_vault.balance, fa, chain);

        TokensOmnichain::change_UserTokenSupply(token, chain, sender, amount, false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
        Margin::remove_borrow(shared_storage, sender, token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        provider_vault.total_borrowed = provider_vault.total_borrowed - (amount as u256);

        accrue(provider_vault, shared_storage, sender, token, chain, provider);
        event::emit(VaultEvent {
            validator: signer::address_of(validator),
            type: utf8(b"Repay"),
            amount: amount,
            sender: sender,
            to: bcs::to_bytes(&utf8(b"0x0")),
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
         });

    }

    public fun bridge_swap(validator: &signer, sender: vector<u8>,  shared_storage:vector<u8>, tokenFrom: String, chainFrom: String, providerFrom: String,  tokenTo: String, chainTo: String, providerTo: String,permission: Permission, recipient: address, amount_in: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let x = borrow_global_mut<GlobalVault>(@dev);
        // Step 1: withdraw tokens of type T from user
        Margin::remove_deposit(shared_storage,sender, tokenFrom, chainFrom, providerFrom, (amount_in as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        
        {
            let provider_vault_from = find_vault(borrow_global_mut<GlobalVault>(@dev), tokenFrom, chainFrom, providerFrom); 
            accrue(provider_vault_from, shared_storage, sender, tokenFrom, chainFrom, providerFrom);
        };

        // Step 2: calculate output amount in Y (simple price * ratio example)
        let metadata_in = TokensMetadata::get_coin_metadata_by_symbol(tokenFrom);
        let metadata_out = TokensMetadata::get_coin_metadata_by_symbol(tokenTo);

        let price_in =  TokensMetadata::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  TokensMetadata::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount_in as u256) * price_in) / price_out;

        // Step 3: update margin/tracking if necessary
        Margin::add_deposit(shared_storage,sender, tokenTo, chainTo, providerTo, (amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        {
            let provider_vault_to = find_vault(borrow_global_mut<GlobalVault>(@dev), tokenTo, chainTo, providerTo); 
        };
    
        event::emit(VaultEvent {
            validator: signer::address_of(validator),
            type: utf8(b"Swap"),
            amount: amount_in,
            sender: sender,
            to: sender,
            token: tokenFrom,
            chain: chainFrom,
            provider: providerFrom,
            time: timestamp::now_seconds(),
         });


        event::emit(SwapVaultEvent {
            amountSwapped: amount_in,
            tokenFrom: tokenFrom,
            chainFrom: chainFrom,
            providerFrom: providerFrom,
            amountReceived: (amount_out as u64),
            tokenTo: tokenTo,
            chainTo: chainTo,
            providerTo: providerTo,        
            time: timestamp::now_seconds(),
         });
    }

    public entry fun bridge_claim_rewards(validator: &signer, sender: vector<u8>,  shared_storage:vector<u8>, token: String, chain: String, provider: String) acquires GlobalVault, Permissions {

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        accrue(provider_vault,shared_storage,sender, token, chain, provider);
        let (rate, reward_index, interest_index, last_updated) = TokensRates::get_vault_raw(token, chain);
        //        return (balance.token, balance.deposited, balance.borrowed, balance.reward_index_snapshot, balance.interest_index_snapshot, balance.last_update)
        let (user_deposited, user_borrowed, user_rewards, _, user_interest, _, _) = Margin::get_user_raw_balance(sender, token, chain, provider);

        let reward_amount = user_rewards;
        let interest_amount = user_interest;


        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(fungible_asset::balance(provider_vault.balance) >= (reward as u64), ERROR_NOT_ENOUGH_LIQUIDITY);
            let fa = TokensCore::withdraw(provider_vault.balance, (reward as u64), chain);
            TokensCore::burn_fa(token, chain, fa, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
            TokensOmnichain::change_UserTokenSupply(token, chain, sender, (reward as u64), true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
          
            event::emit(VaultEvent {
                validator: utf8(b"0x0"),
                type: utf8(b"Claim Rewards"),
                amount: (reward as u64),
                sender: sender,
                to: sender,
                token: token,
                chain: chain,
                provider: provider,
                time: timestamp::now_seconds(),
            });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            Margin::remove_deposit(shared_storage, sender, token, chain, provider, interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            TokensOmnichain::change_UserTokenSupply(token, chain, sender, (interest as u64), false, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 

            let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
            let fa = TokensCore::mint(token, chain, (interest as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core)); 
            TokensCore::deposit(provider_vault.balance, fa, chain);

            event::emit(BridgeVaultEvent {
                type: utf8(b"Pay Interest"),
                validator: signer::address_of(validator),
                amount: (interest as u64),
                sender: sender,
                to: bcs::to_bytes(&utf8(b"0x0")),
                token: token,
                chain: chain,
                provider: provider,
                time: timestamp::now_seconds(),
            });
        };
        Margin::remove_interest(shared_storage, sender, token, chain, provider, (reward_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards(shared_storage, sender, token, chain, provider, (interest_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
    }

    public entry fun swap(signer: &signer, shared_storage: vector<u8>, tokenFrom: String, chainFrom: String, providerFrom:String, amount: u64, tokenTo: String, chainTo:String, providerTo: String) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        Margin::remove_deposit(shared_storage,bcs::to_bytes(&signer::address_of(signer)), tokenFrom, chainFrom, providerFrom, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        
        let x = borrow_global_mut<GlobalVault>(@dev);
        { 
            let provider_vault_from = find_vault(x, tokenFrom, chainFrom, providerFrom); 
            accrue(provider_vault_from, shared_storage,bcs::to_bytes(&signer::address_of(signer)), tokenFrom, chainFrom, providerFrom);
        };

        let metadata_in = TokensMetadata::get_coin_metadata_by_symbol(tokenFrom);
        let metadata_out = TokensMetadata::get_coin_metadata_by_symbol(tokenTo);

        let price_in =  TokensMetadata::get_coin_metadata_price(&metadata_in);   // assumed in USD
        let price_out =  TokensMetadata::get_coin_metadata_price(&metadata_out); // assumed in USD

        let amount_out = ((amount as u256) * price_in) / price_out;

        Margin::add_deposit(shared_storage,bcs::to_bytes(&signer::address_of(signer)), tokenTo, chainTo, providerTo,(amount_out as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        {
            let provider_vault_to = find_vault(x, tokenTo, chainTo, providerTo); 
        };

        event::emit(VaultEvent {
            validator: utf8(b"0x0"),
            type: utf8(b"Swap"),
            amount: amount,
            address: signer::address_of(signer),
            to: shared_storage,
            token: tokenFrom,
            chain: chainFrom,
            provider: providerFrom,
            time: timestamp::now_seconds(),
        });

        event::emit(SwapVaultEvent {
            amountSwapped: amount,
            tokenFrom: tokenFrom,
            chainFrom: chainFrom,
            providerFrom: providerFrom,
            amountReceived: (amount_out as u64),
            tokenTo: tokenTo,
            chainTo: chainTo,
            providerTo: providerTo,        
            time: timestamp::now_seconds(),
         });

    }

    public entry fun deposit(signer: &signer, shared_storage: vector<u8>, token: String, chain: String, provider: String, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let fa = TokensCore::withdraw(primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), amount, chain);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        TokensCore::deposit(provider_vault.balance, fa, chain);
        Margin::add_deposit(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        accrue(provider_vault,shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);

        event::emit(VaultEvent {
            validator: utf8(b"0x0"),
            type: utf8(b"Deposit"),
            amount: amount,
            address: signer::address_of(signer),
            to: shared_storage,
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
        });
    }

    public entry fun withdraw(signer: &signer, shared_storage: vector<u8>, to: address, token: String, chain: String, provider: String, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 
        let fa = TokensCore::withdraw(provider_vault.balance, amount, chain);

        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(to,TokensCore::get_metadata(token)), fa, chain);

      //  let fee_amount = TokensMetadata::get_coin_metadata_market_w_fee(&TokensMetadata::get_coin_metadata_by_symbol(token)) * (amount as u64) / 1000000;
      //  fee::pay_fee<Token>(user, coin::withdraw<Token>(user, fee_amount), utf8(b"Withdraw Fee"));

        Margin::remove_deposit(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin)); 
        accrue(provider_vault, shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);

        event::emit(VaultEvent {
            validator: utf8(b"0x0"),
            type: utf8(b"Withdraw"),
            amount: amount,
            address: signer::address_of(signer),
            to: bcs::to_bytes(&to),
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
        });
    }

    public entry fun borrow(signer: &signer, shared_storage: vector<u8>, to: address, token: String, chain: String, provider: String, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

    //    let valueUSD = getValue(token, (amount as u256));
    //    let (depoUSD, _, _, borrowUSD, _, _, _, _, _, _) = Margin::get_user_total_usd(signer::address_of(sender));

    //    assert!(coin::value(&vault.balance) >= amount, ERROR_NOT_ENOUGH_LIQUIDITY);
    //    assert!(depoUSD >= (valueUSD+borrowUSD), ERROR_BORROW_COLLATERAL_OVERFLOW);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        let fa = TokensCore::withdraw(provider_vault.balance, amount, chain);
        TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(to,TokensCore::get_metadata(token)), fa, chain);

        Margin::add_borrow(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        provider_vault.total_borrowed = provider_vault.total_borrowed + (amount as u256);

        accrue(provider_vault, shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        event::emit(VaultEvent {
            validator: utf8(b"0x0"),
            type: utf8(b"Borrow"),
            amount: amount,
            address: signer::address_of(signer),
            to: bcs::to_bytes(&to),
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
        });
    }


    public entry fun repay(signer: &signer, shared_storage: vector<u8>,token: String, chain: String, provider: String, amount: u64) acquires GlobalVault, Permissions {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        let fa = TokensCore::withdraw(primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), amount, chain);
        TokensCore::deposit(provider_vault.balance, fa, chain);

        Margin::remove_borrow(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        provider_vault.total_borrowed = provider_vault.total_borrowed - (amount as u256);

        accrue(provider_vault, shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        event::emit(VaultEvent {
            validator: utf8(b"0x0"),
            type: utf8(b"Repay"),
            amount: amount,
            address: signer::address_of(signer),
            to: bcs::to_bytes(&utf8(b"0x0")),
            token: token,
            chain: chain,
            provider: provider,
            time: timestamp::now_seconds(),
        });
    }

    public entry fun claim_rewards(signer: &signer, shared_storage: vector<u8>, token: String, chain: String, provider: String) acquires GlobalVault, Permissions {

        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        accrue(provider_vault, shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);
        let (rate, reward_index, interest_index, last_updated) = TokensRates::get_vault_raw(token, chain);
        //        return (balance.token, balance.deposited, balance.borrowed, balance.reward_index_snapshot, balance.interest_index_snapshot, balance.last_update)
        let (user_deposited, user_borrowed, user_rewards, _, user_interest, _, _) = Margin::get_user_raw_balance(bcs::to_bytes(&signer::address_of(signer)), token, chain, provider);

        let reward_amount = user_rewards;
        let interest_amount = user_interest;


        let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

        if(reward_amount > interest_amount){
            let reward = (reward_amount - interest_amount);
            assert!(fungible_asset::balance(provider_vault.balance) >= (reward as u64), ERROR_NOT_ENOUGH_LIQUIDITY);
            let fa = TokensCore::withdraw(provider_vault.balance, (reward as u64), chain);
            TokensCore::deposit(primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), fa, chain);
            event::emit(VaultEvent {
                validator: utf8(b"0x0"),
                type: utf8(b"Claim Rewards"),
                amount: (reward as u64),
                address: signer::address_of(signer),
                to: bcs::to_bytes(&signer::address_of(signer)),
                token: token,
                chain: chain,
                provider: provider,
                time: timestamp::now_seconds(),
            });
        } else{
            let interest = (interest_amount - reward_amount);
            // mby pridat like accumulated_interest do vaultu, pro "pricitavani" interstu, ale teoreticky se to
            // uz ted pricita akorat "neviditelne jelikoz uzivatel bude moct withdraw mene tokenu...
            Margin::remove_deposit(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, interest, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            let fa = TokensCore::withdraw(primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer),TokensCore::get_metadata(token)), (interest as u64), chain);

            let provider_vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider); 

            TokensCore::deposit(provider_vault.balance, fa, chain);

            event::emit(VaultEvent {
            validator: utf8(b"0x0"),
                type: utf8(b"Pay Interest"),
                amount: (interest as u64),
                address: signer::address_of(signer),
                to: bcs::to_bytes(&utf8(b"0x0")),
                token: token,
                chain: chain,
                provider: provider,
                time: timestamp::now_seconds(),
            });
        };
        Margin::remove_interest(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (reward_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        Margin::remove_rewards(shared_storage, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, (interest_amount as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
       
    }

    // gets value by usd
    #[view]
    public fun getValue(resource: String, amount: u256): u256{
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(resource);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(TokensMetadata::get_coin_metadata_oracleID(&metadata));
       // let denom = pow10_u256(TokensMetadata::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return ((amount as u256) * (price as u256)) / TokensMetadata::get_coin_metadata_denom(&metadata)
    }

    // converts usd back to coin value
    #[view]
    public fun getValueByCoin(resource: String, amount: u256): u256{
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(resource);
        //abort(100);
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(TokensMetadata::get_coin_metadata_oracleID(&metadata));
       // let denom = pow10_u256(TokensMetadata::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));
        return (((amount as u256)* TokensMetadata::get_coin_metadata_denom(&metadata)) / (price as u256))
    }

    #[view]
    public fun get_utilization_ratio(deposited: u256, borrowed: u256): u256 {
        //abort(147);
        if (deposited == 0 || borrowed == 0) {
            0
        } else {
            ((borrowed * 100_000_000) / deposited)
        }
    }



    #[view]
    public fun return_vaults_for_token(token: String): Map<String, Map<String, Vault>> acquires GlobalVault {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vaults = borrow_global<GlobalVault>(@dev);

        if (!table::contains(&vaults.balances, token)) {
            abort ERROR_INVALID_TOKEN
        };

        *table::borrow(&vaults.balances, token)
    }


    #[view]
    public fun return_vaults_for_token_on_chain(token: String, chain: String): Map<String, Vault> acquires GlobalVault {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vaults = borrow_global<GlobalVault>(@dev);

        if (!table::contains(&vaults.balances, token)) {
            abort ERROR_INVALID_TOKEN
        };
        
        let token_table = table::borrow(&vaults.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

       *map::borrow(token_table, &chain)
    }


    #[view]
    public fun return_vaults_for_token_on_chain_with_provider(token: String, chain: String, provider: String): Vault acquires GlobalVault {
        assert!(exists<GlobalVault>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vaults = borrow_global<GlobalVault>(@dev);

        if (!table::contains(&vaults.balances, token)) {
            abort ERROR_INVALID_TOKEN
        };
        
        let token_table = table::borrow(&vaults.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

        let chain_map = map::borrow(token_table, &chain);

        if (!map::contains_key(chain_map, &provider)) {
            abort ERROR_PROVIDER_DOESNT_SUPPORT_THIS_TOKEN_ON_THIS_CHAIN
        };

        *map::borrow(chain_map, &provider)
    }


/*    #[view]
    public fun get_complete_vault<T, X:store>(tokenStr: String,): CompleteVault acquires GlobalVault {
        let vault = get_vaultUSD<T>(tokenStr);
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);;
        CompleteVault { vault: vault, coin: CoinTypes::get_coin_data<T>(), w_fee: TokensMetadata::get_coin_metadata_market_w_fee(&metadata), Metadata: metadata  }
    }


    #[view]
    public fun get_vault_raw(vaultStr: String): (u256) acquires VaultRegistry {
        let vault = table::borrow(&borrow_global<VaultRegistry>(@dev).vaults, vaultStr);
        (vault.total_borrowed)
    }

    #[view]
    public fun get_vaultUSD(token: String, chain: String, provider: String): VaultUSD acquires GlobalVault, VaultRegistry {
        assert!(exists<GlobalVault<T>>(@dev), ERROR_VAULT_NOT_INITIALIZED);
        let vault = borrow_global<GlobalVault<T>>(@dev);
        let balance = coin::value(&vault.balance);
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);

        let vault_total = return_vaults_for_token_on_chain_with_provider(token, chain, provider);
        let utilization = get_utilization_ratio(FungibleStore::amount(&vault_total.balance), vault_total.total_borrowed);

        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(TokensMetadata::get_coin_metadata_oracleID(&metadata));

        let (lend_apy, _, _) = QiaraMath::compute_rate(
                utilization,
                (TokensMetadata::get_coin_metadata_market_rate(&metadata) as u256),
                (TokensMetadata::get_coin_metadata_rate_scale(&metadata, true) as u256), // pridat check jestli to je borrow nebo lend
                true,
                5
            );

        let (borrow_apy, _, _) = QiaraMath::compute_rate(
                utilization,
                (TokensMetadata::get_coin_metadata_market_rate(&metadata) as u256),
                (TokensMetadata::get_coin_metadata_rate_scale(&metadata, false) as u256), // pridat check jestli to je borrow nebo lend
                false,
                5
            );
       
        VaultUSD {tier: TokensMetadata::get_coin_metadata_tier(&metadata), oracle_price: (price as u128), oracle_decimals: (price_decimals as u8), total_deposited: vault_total.total_deposited,balance: balance, borrowed: vault_total.total_borrowed, utilization: utilization, rewards: lend_apy, interest: borrow_apy, fee: get_withdraw_fee(utilization)}
    }*/


    #[view]
    public fun get_withdraw_fee(utilization: u256): u256 {
        let u_bps = utilization * 100; // convert % to basis points
        let u_bps2 = u_bps;
        if(u_bps2 > 10000){
            u_bps2 = 10000;
        };
        let bonus = ((u_bps) * 4_000) / (20000 - u_bps2);
        return (bonus as u256)
    }

    fun tttta(number: u64){
        abort(number);
    }


    public fun accrue(vault: &mut Vault, owner: vector<u8>, sub_owner: vector<u8>, token: String, chain: String, provider: String) acquires Permissions {
        // staci fetchovat jen jeden vault teoreticky? protoze z nej poterbuju ty rewards a interests indexy? a to pak previst na token A a B... ?
        let (lend_rate, reward_index, interest_index, last_updated) = TokensRates::get_vault_raw(token, chain); // CHECK

        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
        let utilization = get_utilization_ratio((fungible_asset::balance(vault.balance) as u256), vault.total_borrowed);

        TokensRates::accrue_global(token, chain, (lend_rate as u256), (TokensMetadata::get_coin_metadata_rate_scale((&metadata), false) as u256), (utilization as u256), (fungible_asset::balance(vault.balance) as u256), (vault.total_borrowed as u256), TokensRates::give_permission(&borrow_global<Permissions>(@dev).tokens_rates));

        let scale: u128 = 1_000_000;
        let (user_deposited, user_borrowed, user_rewards,user_reward_index, user_interest, user_interest_index, _) = Margin::get_user_raw_balance(owner, token, chain, provider); // CHECK


        if ((reward_index) > (user_reward_index as u128)) {
            let delta_reward = reward_index - (user_reward_index as u128);
            let (r_token, r_chain, r_provider) = RI::get_user_raw_rewards(owner);
            if((((user_deposited as u128) * delta_reward) / scale) > 0){
                let user_delta_reward_value  = ((((user_deposited as u128) * delta_reward) / scale) as u256);
                let receive_rewards_in_A_tokens = getValueByCoin(r_token, getValue(token, user_delta_reward_value));
                Margin::add_rewards(owner, sub_owner, r_token, r_chain, r_provider, (receive_rewards_in_A_tokens as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_reward_index(owner, sub_owner, r_token, r_chain, r_provider, (reward_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_time(owner, sub_owner, r_token, r_chain, r_provider, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
        };

        if ((interest_index) > (user_interest_index as u128)) {

            let delta_interest = interest_index - (user_interest_index as u128);
            let (i_token, i_chain, i_provider) = RI::get_user_raw_interests(owner);
            if((((user_borrowed as u128) * delta_interest) / scale) > 0){
                let user_delta_interest_value = ((((user_borrowed as u128) * delta_interest) / scale) as u256);
                let pay_interest_in_B_tokens = getValueByCoin(i_token, getValue(token, user_delta_interest_value));
                Margin::add_interest(owner, sub_owner, i_token, i_chain, i_provider, (pay_interest_in_B_tokens as u256) , Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_interest_index(owner, sub_owner, i_token, i_chain, i_provider, (interest_index as u256), Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
                Margin::update_time(owner, sub_owner, i_token, i_chain, i_provider, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
        }; 
    }
    // Initialize storages for a specific token and chain
    fun find_vault(vaults: &mut GlobalVault, token: String, chain: String, provider: String): &mut Vault {
        ChainTypes::ensure_valid_chain_name(chain);
        
        let metadata = TokensCore::get_metadata(token);

        if (!table::contains(&vaults.balances, token)) {
            table::add(&mut vaults.balances, token, map::new<String, Map<String,Vault>>());
        };
        let token_table = table::borrow_mut(&mut vaults.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            map::add( token_table, chain, map::new<String, Vault>());
        };

        let chain_map = map::borrow_mut(token_table, &chain);

        if (!map::contains_key(chain_map, &provider)) {
            map::add( chain_map, provider, Vault {total_borrowed: 0, balance: primary_fungible_store::ensure_primary_store_exists<Metadata>(@dev, metadata)});
        };

        map::borrow_mut(chain_map, &provider)
    }
}
