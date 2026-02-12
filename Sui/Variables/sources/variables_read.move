module 0x0::QiaraVariablesReadV1 {
    use std::string::String;
    use 0x0::QiaraVariablesV1::{AdminCap, FriendCap, Registry};
    use sui::bcs;

    // --- Getters ---
    public fun get_variable_to_u8(registry: &Registry, header: String, name: String): u8 {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u8(&mut bytes)
    }
    public fun get_variable_to_u16(registry: &Registry, header: String, name: String): u16 {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u16(&mut bytes)
    }
    public fun get_variable_to_u32(registry: &Registry, header: String, name: String): u32 {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u32(&mut bytes)
    }
    public fun get_variable_to_u64(registry: &Registry, header: String, name: String): u64 {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u64(&mut bytes)
    }
    public fun get_variable_to_u128(registry: &Registry, header: String, name: String): u128 {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u128(&mut bytes)
    }
    public fun get_variable_to_u256(registry: &Registry, header: String, name: String): u256 {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u256(&mut bytes)
    }
    public fun get_variable_to_vecu8(registry: &Registry, header: String, name: String): vector<u8> {
        let mut data = 0x0::QiaraVariablesV1::get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_vec_u8(&mut bytes)
    }
}