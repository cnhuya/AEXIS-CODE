module dev::QiaraAutoHelpersV1 {
    use supra_framework::event;
    use std::timestamp;
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use dev::QiaraPerpsV32::{Self as Perps};
    use dev::QiaraVaultsV37::{Self as Vaults};
    use dev::QiaraAutoRegistryV1::{Self as Auto_Registry};
    use std::table::{Self, Table};

    use dev::QiaraVerifiedTokensV42::{Self as VerifiedTokens, Tier, CoinData, VMetadata, Access as VerifiedTokensAccess};

    /// === INIT ===
    /// === STRUCTS ===
    #[event]
    struct AutoRegistration has copy, drop, store {
        address: address,
        function: String,
        uid: String,
        duration: u64,
        i:u64,
        size: u256,
        limit: u256,
        leverage: u64,
        side: String,
        type: String,
        time: u64,
    }
    /// === FUNCTIONS ===
    public entry fun stop_automated_transaction(address: address, uid: String)  {
        Auto_Registry::stop_automated_transaction(address, uid);
    }
  
    public entry fun automated_trade<T: store, A,B>(address: address, size:u256, leverage: u64, limit: u256, side: String, type: String, i: u64, duration: u64, uid: String){
        Auto_Registry::register_automated_transaction(address, i, duration, uid);
        if(Auto_Registry::validate_automated_transaction(address, uid)){
            Perps::trade<T, A,B>(address, size, leverage, limit, side, type);
        };

        event::emit(AutoRegistration {
            address: address,
            function: utf8(b"Trade"),
            uid: uid,
            duration: duration,
            i:i,
            size: size,
            limit: limit,
            leverage: leverage,
            side: side,
            type: type,
            time: timestamp::now_seconds(),
        });

    }

    public entry fun automated_swap<T: store, X,A,B>(signer: &signer, size:u256, i: u64, limit: u256, duration: u64, uid: String) {
        Auto_Registry::register_automated_transaction(signer::address_of(signer), i, duration, uid);
        if(Auto_Registry::validate_automated_transaction(signer::address_of(signer), uid)){
            Vaults::swap<T,A,X,B>(signer, (size as u64));
        };
        event::emit(AutoRegistration {
            address: signer::address_of(signer),
            function: utf8(b"Swap"),
            uid: uid,
            duration: duration,
            i:i,
            size: size,
            limit: limit,
            leverage: 0,
            side: utf8(b"---"),
            type: utf8(b"---"),
            time: timestamp::now_seconds(),
        });

    }


}
