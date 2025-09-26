module dev::QiaraSwap{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;

    use dev::QiaraMarginV1::{Self as Margin, Access as MarginAccess};
    use dev::QiaraVerifiedTokensV1::{Self as VerifiedTokens};
    use dev::QiaraVaultsV1::{Self as Vaults};

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(s: &signer, access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key {
        margin: MarginAccess
    }

/// === STRUCTS ===
  
  

/// === FUNCTIONS ===
    fun init_module(admin: &signer){

    }

    public fun swap<A,B, X>(address: address, amount: u64 cap: Permission){
        Vaults::withdraw<A, X>(address, amount);

        let metadata = VerifiedTokens::get_coin_metadata_by_res(&type_info::type_name<A>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
        let denom = Math::pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

        let usd_value_A = (amount as u256) * (price as u256) / denom;

        let metadata = VerifiedTokens::get_coin_metadata_by_res(&type_info::type_name<B>());
        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(VerifiedTokens::get_coin_metadata_oracle(&metadata));
        let denom = Math::pow10_u256(VerifiedTokens::get_coin_metadata_decimals(&metadata) + (price_decimals as u8));

        let token_value_B = usd_value_A * denom / (price as u256);
        
    }



}
