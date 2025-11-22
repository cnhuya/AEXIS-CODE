module dev::QiaraAny {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use aptos_std::type_info;
    use aptos_std::from_bcs;
    use std::bcs::{Self as bc};


/// === STRUCTS ===
    struct Any has drop, store, copy { type: String, data: vector<u8> }

    fun constructor_any<T>(value: vector<u8>): Any {
        Any { type: type_info::type_name<T>(), data: value }
    }

    public fun make_any<T>(value: T): Any {
        constructor_any<T>(bc::to_bytes(&value))
    }

/// === VIEW FUNCTIONS ===
   #[view]
    public fun expect_u8(data: vector<u8>): u8 {
        from_bcs::to_u8(data)
    }
    #[view]
    public fun expect_u16(data: vector<u8>): u16 {
        from_bcs::to_u16(data)
    }
    #[view]
    public fun expect_u32(data: vector<u8>): u32 {
        from_bcs::to_u32(data)
    }
    #[view]
    public fun expect_u64(data: vector<u8>): u64 {
        from_bcs::to_u64(data)
    }
    #[view]
    public fun expect_u128(data: vector<u8>):  u128 {
        from_bcs::to_u128(data)
    }
    #[view]
    public fun expect_u256(data: vector<u8>): u256 {
        from_bcs::to_u256(data)
    }
    #[view]
    public fun expect_bool(data: vector<u8>): bool {
        from_bcs::to_bool(data)
    }
    #[view]
    public fun expect_address(data: vector<u8>): address {
        from_bcs::to_address(data)
    }
    #[view]
    public fun expect_bytes(data: vector<u8>): vector<u8> {
        from_bcs::to_bytes(data)
    }
    #[view]
    public fun expect_string(data: vector<u8>): string::String {
        from_bcs::to_string(data)
    }
}
