module dev::QiaraTokensBridgeHandlerV3{
    use std::signer;
    use std::bcs;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use aptos_std::from_bcs;
    use supra_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use std::timestamp;
    use supra_framework::event;

    use dev::QiaraChainTypesV15::{Self as ChainTypes};
    use dev::QiaraTokensBridgeStorageV3::{Self as TokensBridgeStorage, Access as TokensBridgeStorageAccess};
    use dev::QiaraTokensCoreV3::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensTiersV3::{Self as TokensTiers};
    use dev::QiaraTokensMetadataV3::{Self as TokensMetadata};
    use dev::QiaraTokensFeeVaultV3::{Self as TokensFeeVault, Access as TokensFeeVaultAccess};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_ZERO_AMOUNT: u64 = 2;
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

    struct Permissions has key {
        tokens_bridge_storage_access: TokensBridgeStorageAccess,
        tokens_core_access: TokensCoreAccess,
        token_fee_vault_access: TokensFeeVaultAccess,
    }

// === EVENTS === //
    #[event]
    struct BridgeEvent has copy, drop, store {
        validator: address,
        amount: u64,
        address: vector<u8>,
        token: String,
        chain: String,
        time: u64
    }

    #[event]
    struct RequestBridgeEvent has copy, drop, store {
        validator: address,
        amount: u64,
        address: vector<u8>,
        token: String,
        chain: String,
        time: u64
    }

// === INIT === //
    fun init_module(admin: &signer) {
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { tokens_bridge_storage_access: TokensBridgeStorage::give_access(admin), tokens_core_access: TokensCore::give_access(admin), token_fee_vault_access: TokensFeeVault::give_access(admin)});
        };
    }


// === FUNCTIONS === //
    // Native Functions
        // Any user can call, to reques bridging tokens from Supra to other chains
        public entry fun n_bridge_to<Token, Chain>(user: &signer, amount: u64) acquires Permissions {
            assert!(amount > 0, ERROR_ZERO_AMOUNT);

            let coins = coin::withdraw<Token>(user, amount);
            TokensBridgeStorage::lock<Token, Chain>(user, coins, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));

            event::emit(RequestBridgeEvent {
                amount, 
                validator: signer::address_of(user), 
                token: type_info::type_name<Token>(), 
                address: bcs::to_bytes(&signer::address_of(user)), 
                chain: ChainTypes::convert_chainType_to_string<Chain>(),
                time: timestamp::now_seconds() 
            });
        }

    // Permissioneless functions
        // Only validator can call, to request bridging tokens from Supra to other chains
        public fun p_bridge_to<Token: store, Chain>(banker: &signer, cap: Permission, recipient: vector<u8>, amount: u64) acquires Permissions {
            assert!(amount > 0, ERROR_ZERO_AMOUNT);

            let who = signer::address_of(banker);
            //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);
            TokensBridgeStorage::p_burn<Token, Chain>(recipient, amount, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
            let coins = TokensCore::mint<Token, Chain>(amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core_access));
            TokensBridgeStorage::lock<Token, Chain>(banker, coins, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));

            event::emit(RequestBridgeEvent {
                amount, 
                validator: signer::address_of(banker), 
                token: type_info::type_name<Token>(), 
                address: recipient, 
                chain: ChainTypes::convert_chainType_to_string<Chain>(),
                time: timestamp::now_seconds() 
            });
      }


    // Only validator can call, to mint new bridged tokens on Supra
    public fun finalize_bridge_from<Token: store, Chain>(banker: &signer, cap: Permission, recipient: vector<u8>, amount: u64) acquires Permissions {
        let who = signer::address_of(banker);
        //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);

        if(coin::is_account_registered<Token>(from_bcs::to_address(recipient)) == false){
            TokensBridgeStorage::p_mint<Token, Chain>(recipient, amount, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
        } else{
            let coins = TokensCore::mint<Token, Chain>(amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core_access));
            coin::deposit<Token>(from_bcs::to_address(recipient), coins);
        };

        event::emit(BridgeEvent {
             amount, 
             validator: signer::address_of(banker), 
             token: type_info::type_name<Token>(), 
             address: recipient, 
             chain: ChainTypes::convert_chainType_to_string<Chain>(),
             time: timestamp::now_seconds() 
        });

    }

    // Only validator can call, to burn tokens bridged out form Supra
    public fun finalize_bridge_to<Token: store, Chain>(banker: &signer, cap: Permission, recipient: vector<u8>, amount: u64) acquires Permissions  {
        let who = signer::address_of(banker);
        //assert!(vector::contains(&Chains::get_supra_bankers(), &who), ERROR_NOT_VALIDATOR);
        let amount_u256 = (amount as u256);

        let bridge_fee = (TokensTiers::bridge_fee(TokensMetadata::get_coin_metadata_tier(&TokensMetadata::get_coin_metadata<Token>())) as u256);

        let fee_amount = (amount_u256*bridge_fee) / 1_000_000;
        let final_amount = amount_u256-fee_amount;

        let fee_coins = TokensCore::mint<Token, Chain>((fee_amount as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core_access));
        TokensFeeVault::pay_fee<Token>(recipient, fee_coins, utf8(b"bridge_fee"), TokensFeeVault::give_permission(&borrow_global<Permissions>(@dev).token_fee_vault_access));

        TokensBridgeStorage::p_burn<Token, Chain>(recipient, (final_amount as u64), TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));

        event::emit(BridgeEvent {
             amount: (final_amount as u64), 
             validator: signer::address_of(banker), 
             token: type_info::type_name<Token>(), 
             address: recipient, 
             chain: ChainTypes::convert_chainType_to_string<Chain>(),
             time: timestamp::now_seconds() 
        });

    }
}


