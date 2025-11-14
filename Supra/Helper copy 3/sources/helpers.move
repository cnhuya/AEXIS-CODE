module dev::QiaraAutoHelpers {
    use dev::QiaraPerpsV29::{Self as Perps};
    use dev::QiaraVaultsV43::{Self as Vaults};
    use dev::QiaraAutoRegistry::{Self as Auto_Registry};

    /// === INIT ===
    /// === STRUCTS ===

    /// === FUNCTIONS ===
    public fun auto_trade<T: store, A,B>(address: address, size:u256, leverage: u64, limit: u256, side: String, type: String, i: u64, duration: u64){
        Perps::trade<T: store, A,B>(address, size, leverage, limit, side, type);
        Auto_Registry::register_automated_transaction(i, duration);
    }

    public fun auto_swap<T: store, A,B>(address: address, size:u256, i: u64, duration: u64) {
        Vaults::swap<T: store, A,B>(address, size);
        Auto_Registry::register_automated_transaction(i, duration);
    }
}
