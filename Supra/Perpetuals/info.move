module dev::QiaraInfoV12{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info::{Self, TypeInfo};
    use std::table;
    use supra_oracle::supra_oracle_storage;
    use dev::QiaraMathV9::{Self as QiaraMath};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;

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
    
    struct FullInfo has store, key{
        market: Market,
        tokenomics: Tokenomics,
        contract: Contract,
        tier: Tier,
        price: Price,
        offchainID: u64,
        creation: u64,
    }

    struct Price has store, key{
        oracleID: u64,
        price: u64,
        denom: u64,
    }

    struct Info has store, key{
        market: Market,
        tokenomics: Tokenomics,
        oracleID: u64,
        offchainID: u64,
        creation: u64,
    }

    struct Market has store, key{
        mc: u128,
        fdv: u128,
        fdv_mc: u128,
    }

    struct Tokenomics has store, key{
        max_supply: u128,
        circulating_supply: u128,
        total_supply: u128,
    }

    struct Contract has store, key{
        max_size: u64,
        min_size: u64,
        max_leverage: u64,
    }

    struct Tier has store, key{
        tier: String,
        leverage_cut: u64,
        profit_fee: u64,
    }


/// === INIT ===
    fun init_module(admin: &signer){

    }

/// === ENTRY FUNCTIONS ===
    public entry fun create_info<T: store>(admin: &signer, creation: u64 offchainID: u64, oracleID: u64, max_supply: u128, circulating_supply: u128, total_supply: u128) acquires Info {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        let market = Market { mc: mc, fdv: fdv, fdv_mc: fdv_mc };
        let tokenomics = Tokenomics { max_supply: max_supply, circulating_supply: circulating_supply, total_supply: total_supply };

        move_to(admin, Info<T> { market: market, tokenomics: tokenomics, oracleID: oracleID, offchainID: offchainID });
    }

    public entry fun update_tokenomics<T: store>(admin: &signer, max_supply: u128, circulating_supply: u128, total_supply: u128) acquires Info {
       
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        let info = borrow_global_mut<Info<T>>(signer::address_of(admin));
        let tokenomics = Tokenomics { max_supply: max_supply, circulating_supply: circulating_supply, total_supply: total_supply };

        info.tokenomics = tokenomics;
    }

/// === HELPER FUNCTIONS ===
    fun calculate_market<T: store>(): Market acquires Info{
        let info = borrow_global<Info<T>>(@dev);

        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());

        let mc = (info.tokenomics.circulating_supply as u128) * price / (denom as u128);
        let fdv = (info.tokenomics.max_supply as u128) * price / (denom as u128);
        let fdv_mc = if (mc > 0) { (fdv * 100) / mc } else { 0 };

        Market { mc: mc, fdv: fdv, fdv_mc: fdv_mc }
    }

    fun calculate_asset_credit<T: store>(): u128 acquires Info{
        let info = borrow_global<Info<T>>(@dev);

        let metadata = VerifiedTokens::get_coin_metadata_by_res(type_info::type_name<T>());

        let mc = (info.tokenomics.circulating_supply as u128) * price / (denom as u128);
        let fdv = (info.tokenomics.max_supply as u128) * price / (denom as u128);
        let fdv_mc = if (mc > 0) { (fdv * 100) / mc } else { 0 };

        mc  * (mc / fdv) * (fdv_mc/100)

    }


    fun associate_tier(credit: u128): Tier{
        if (credit >= 25_000_000){
            return Tier { tier: String::utf8(b"Diamond"), leverage_cut: 0, profit_fee: 75000 };
        } else if (credit >= 12_500_000){
            return Tier { tier: String::utf8(b"Gold"), leverage_cut: 10, profit_fee: 65000 };
        } else if (credit >= 7_500_000){
            return Tier { tier: String::utf8(b"Silver"), leverage_cut: 25, profit_fee: 55000 };
        } else if (credit >= 5_000_000){
            return Tier { tier: String::utf8(b"Silver"), leverage_cut: 50, profit_fee: 45000 };
        } else if (credit >= 1_000_000){
            return Tier { tier: String::utf8(b"Silver"), leverage_cut: 75, profit_fee: 35000 };
        } else {
            return Tier { tier: String::utf8(b"Bronze"), leverage_cut: 90, profit_fee: 25000 };
        }
    }


/// === VIEW FUNCTIONS ===
    #[view]
    public fun view_full_info<T: store>(): FullInfo<T> acquires UserBook {
        let info = borrow_global<Info<T>>(@dev);

        let market = calculate_market<T>();

        let (price, price_decimals, _, _) = supra_oracle_storage::get_price(info.oracleID);
        let denom = Math::pow(10u64, price_decimals);

        FullInfo {
            market: market,
            tokenomics: info.tokenomics,
            contract: Contract { max_size: 1000000, min_size: 1000, max_leverage: 100 },
            tier: Tier { tier: String::utf8(b"Diamond"), leverage_cut: 5, profit_fee: 10 },
            price: Price { oracleID: info.oracleID, price: price, denom: denom },
            offchainID: info.offchainID,
            creation: info.creation,
        }
    }
}
