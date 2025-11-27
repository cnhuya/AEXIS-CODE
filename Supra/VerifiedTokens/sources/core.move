module dev::QiaraTokensCoreV3{
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::string::{Self as string, String, utf8};
    use supra_framework::managed_coin::{Self};
    use supra_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};
    use std::type_info::{Self, TypeInfo};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::option::{Option};
    use dev::QiaraMathV9::{Self as Math};
    use dev::QiaraCoinTypesV15::{Self as TokensType, Bitcoin, Ethereum, Solana, Sui, Deepbook, Injective, Aerodrome, Virtuals, Supra, USDT, USDC};
    use dev::QiaraTokensMetadataV3::{Self as TokensMetadata};
    use dev::QiaraTokensBridgeStorageV3::{Self as TokensBridgeStorage, Access as TokensBridgeStorageAccess};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_INVALID_COIN_TYPE: u64 = 2;
    const ERROR_UNKNOWN_ERROR: u64 = 3;
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
    
// === STRUCTS === //

    struct Permissions has key {
        tokens_bridge_storage_access: TokensBridgeStorageAccess,
    }

    struct Capabilities<Token> has key {
        burn_cap: BurnCapability<Token>,
        mint_cap: MintCapability<Token>,
        freeze_cap: FreezeCapability<Token>,
    }

    // View Struct
    struct CoinData has store, key, drop {
        resource: String,
        name: String,
        symbol: String,
        decimals: u8,
        supply: Option<u128>, 
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { tokens_bridge_storage_access: TokensBridgeStorage::give_access(admin)});
        };

        init_coin<Bitcoin>(admin, utf8(b"Qiara Bitcoin"),   utf8(b"QBTC"), 8, 1_231_006_505, 0, 21_000_000, 19_941_253, 19_941_253, 1);
        init_coin<Ethereum>(admin, utf8(b"Qiara Ethereum"), utf8(b"QETH"), 8, 1_438_269_983, 1, 120_698_129, 120_698_129, 120_698_129, 1);
        init_coin<Solana>(admin,     utf8(b"Qiara SUI"),       utf8(b"QSOL"), 8, 1_584_316_800, 10, 614_655_961, 559_139_255, 614_655_961, 1);
        init_coin<Sui>(admin,    utf8(b"Qiara USDC"),      utf8(b"QSUI"), 8, 1_683_062_400, 90, 10_000_000_000, 3_680_742_933, 10_000_000_000, 1);
        init_coin<Deepbook>(admin,    utf8(b"Qiara USDT"),      utf8(b"QDEEP"), 8,  1_683_072_000, 491, 10_000_000_000, 4_368_147_611, 10_000_000_000, 1);
        init_coin<Injective>(admin,    utf8(b"Qiara USDT"),      utf8(b"QINJ"), 8, 1_636_416_000, 121, 100_000_000, 100_000_000, 100_000_000, 1);
        init_coin<Virtuals>(admin,    utf8(b"Qiara USDT"),      utf8(b"QVIRTUALS"), 8, 1_614_556_800, 524, 1_000_000_000, 656_082_020, 1_000_000_000, 1);
        init_coin<Supra>(admin,    utf8(b"Qiara USDT"),      utf8(b"QSUPRA"), 8, 1_732_598_400, 500, 100_000_000_000, 21_000_700_000, 80_600_180_397, 1);
        init_coin<USDT>(admin,    utf8(b"Qiara USDT"),      utf8(b"QUSDT"), 8, 0, 47, 185_977_352_465, 185_977_352_465, 185_977_352_465, 255);
        init_coin<USDC>(admin,    utf8(b"Qiara USDT"),      utf8(b"QUSDC"), 8, 0, 47, 76_235_696_160, 76_235_696_160, 76_235_696_160, 255);

    }
// === INIT COIN === //
    public entry fun init_coin<T: store>(admin: &signer, name: String, symbol: String, decimals: u8, creation: u64,oracleID: u32, max_supply: u128, circulating_supply: u128, total_supply: u128, stable:u8) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Capabilities<T>>(signer::address_of(admin)) && !coin::is_coin_initialized<T>()) {
            let (burn_cap, freeze_cap, mint_cap) = coin::initialize<T>(
                admin,
                name,
                symbol,
                decimals,
                true
            );

            register<T>(admin);

            let caps = Capabilities<T> { burn_cap, mint_cap, freeze_cap };
            move_to(admin, caps);
            
            TokensMetadata::create_metadata<T>(admin, creation, oracleID, max_supply, circulating_supply, total_supply, stable);
            TokensBridgeStorage::init_lock<T>(admin);

        };

    }
// === HELPERS === //
    //User ownership mint/burn Interface

        public entry fun redeem<Token: store, Chain>(signer: &signer) acquires Capabilities, Permissions {
            let amount = (TokensBridgeStorage::return_balance<Token, Chain>(bcs::to_bytes(&signer::address_of(signer))) as u64);
            let coins = coin::mint(amount, &borrow_global<Capabilities<Token>>(@dev).mint_cap);
            TokensBridgeStorage::p_burn<Token, Chain>(bcs::to_bytes(&signer::address_of(signer)), amount, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
            coin::deposit<Token>(signer::address_of(signer), coins);
        }

        public fun mint<Token: store, Chain>(amount: u64, perm: Permission): Coin<Token> acquires Capabilities, Permissions {
            TokensBridgeStorage::change_TokenSupply<Token, Chain>(amount, true, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
            coin::mint(amount, &borrow_global<Capabilities<Token>>(@dev).mint_cap)
        }

        public fun burn<Token: store, Chain>(coins: Coin<Token>, perm: Permission) acquires Capabilities, Permissions{
            let value = coin::value(&coins);
            coin::burn(coins, &borrow_global<Capabilities<Token>>(@dev).burn_cap);
            TokensBridgeStorage::change_TokenSupply<Token, Chain>(value, false, TokensBridgeStorage::give_permission(&borrow_global<Permissions>(@dev).tokens_bridge_storage_access));
        }


    // User coin registration
    public entry fun register<Token>(user: &signer) {
        managed_coin::register<Token>(user);
    }

// === FUNCTIONS === //

    // Convenience transfer (standard user transfer)
    public entry fun transfer<Token, Chain>(sender: &signer, recipient: address, amount: u64) {
        coin::transfer<Token>(sender, recipient, amount);
    }

// === UNSAFE HELPER FUNCTIONS === //
    // For testing

    public entry fun unsafe_withdraw_to<Token: store, Chain>(banker: &signer,recipient: address, amount: u64) acquires Capabilities, Permissions {
        let who = signer::address_of(banker);
        assert!(who == @0xad4689eb401dbd7cff34d47ce1f2c236375ae7481cdaca884a0c2cdb35b339b0, ERROR_NOT_VALIDATOR);

        let coins = mint<Token, Chain>(amount, give_permission(&give_access(banker)));
        coin::deposit<Token>(recipient, coins);
    }

// === VIEW FUNCTIONS === //
    #[view]
    public fun balance_of<T>(addr: address): u64 {
        coin::balance<T>(addr)
    }

 // === GET COIN DATA === //
        #[view]
        public fun get_coin_data<Token>(): CoinData {
            let type = type_info::type_name<Token>();
            CoinData { resource: type, name: coin::name<Token>(), symbol: coin::symbol<Token>(), decimals: coin::decimals<Token>(), supply: coin::supply<Token>() }
        }

        public fun get_coin_type<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.resource
        }

        public fun get_coin_name<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.name
        }

        public fun get_coin_symbol<Token>(): String {
            let coin_data = get_coin_data<Token>();
            coin_data.symbol
        }

        public fun get_coin_decimals<Token>(): u8 {
            let coin_data = get_coin_data<Token>();
            coin_data.decimals
        }

        public fun get_coin_denom<Token>(): u256 {
            let coin_data = get_coin_data<Token>();
            Math::pow10_u256((coin_data.decimals as u8))
        }

        public fun get_coin_supply<Token>(): Option<u128> {
            let coin_data = get_coin_data<Token>();
            coin_data.supply
        }



}
