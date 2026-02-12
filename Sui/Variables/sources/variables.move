module 0x0::QiaraVariablesV1 {
    use std::string::String;
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};
    use sui::tx_context::{Self, TxContext};
    use 0x0::QIARA_ZKV1::{Self as zk};

    //upgrade cap: 0x5b8ff41622419fe9b90637bae670f61467a4700059e2ffd42b05a59aac49e77c
    //admin cap: 0x695abee45ef805009646ac00096054e60d7d8c7e1e7443c2d6f13a429327baaf
    //registry: 0xa6683bb4ca583f2e4f386d647031d7b63a5022e9467f9be14fe4687493fb7252
    //0x83252568a8d45b56004947ae146e24e4d4d9967f5d60ffe489a72abecaa6a2bb
    //friend cap: 0x4bc25726825bc6dbaa8a15492c07eb510cc1cd18c8d5834347627fb9aef6a5d8
    // --- Errors ---
    const ERegistryLocked: u64 = 0;

    // --- Structs ---
    public struct AdminCap has key, store { id: UID }
    public struct FriendCap has key, store { id: UID }

    public struct Registry has key {
        id: UID,
        data: Table<String, VecMap<String, vector<u8>>>,
        is_locked: bool 
    }

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));

        let registry = Registry {
            id: object::new(ctx),
            data: table::new(ctx),
            is_locked: false 
        };
        transfer::share_object(registry);
    }

    // --- Authorization Helpers ---

    /// Allows Admin to mint a FriendCap for another module or account.
    public entry fun issue_friend_cap(_: &AdminCap, recipient: address, ctx: &mut TxContext) {
        let cap = FriendCap { id: object::new(ctx) };
        transfer::transfer(cap, recipient);
    }

    // --- Core Logic (Internal) ---

    /// We move the actual insertion logic here to avoid code duplication.
    fun internal_add(registry: &mut Registry, header: String, name: String, data: vector<u8>) {
        assert!(!registry.is_locked, ERegistryLocked);

        if (!table::contains(&registry.data, header)) {
            let mut map = vec_map::empty<String, vector<u8>>();
            vec_map::insert(&mut map, name, data);
            table::add(&mut registry.data, header, map);
        } else {
            let map = table::borrow_mut(&mut registry.data, header);
            if (vec_map::contains(map, &name)) {
                let (_, _) = vec_map::remove(map, &name);
            };
            vec_map::insert(map, name, data);
        }
    }

    // --- Entry Points ---

    public entry fun admin_add_variable(_: &AdminCap, registry: &mut Registry, header: String, name: String, data: vector<u8>) {
        internal_add(registry, header, name, data);
    }

    public fun friend_add_variable(registry: &mut Registry, header: String, name: String, data: vector<u8>, zk_state: &mut zk::State, public_inputs: vector<u8>, proof_points: vector<u8>) {
        zk::verifyZK(zk_state, public_inputs, proof_points);
        internal_add(registry, header, name, data);
    }

    public entry fun lock_registry(_: &AdminCap, registry: &mut Registry) {
        registry.is_locked = true;
    }

    // --- Getters ---
    public fun get_variable(registry: &Registry, header: String, name: String): vector<u8> {
        let map = table::borrow(&registry.data, header);
        *vec_map::get(map, &name)
    }
}