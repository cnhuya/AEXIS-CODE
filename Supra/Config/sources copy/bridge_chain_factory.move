module dev::AexisBridgeV1 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info;
    use aptos_std::from_bcs;
    use supra_framework::event;

    /// Admin address constant
    const ADMIN: address = @dev; // <-- replace with real admin address

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_VALIDATOR_IS_ALREADY_ALLOWED: u64 = 3;

    struct ConfiguratorCap has store, key { }

    struct BlockTime has store, key, drop {
        time: u64
    }

    struct ChainRegistry has store, key, copy {
        registry: vector<Chain>
    }

    struct Chain has key, drop, store {
        id: u8,
        name: String,
        symbol: String,
        validators: vector<vector<u8>>,
    }

    #[event]
    struct LiquidationEvent has copy, drop, store {
        borrower: address,
        liquidator: address,
        repaid: u64,
        collateral_seized: u64,
    }

    public fun init_module(admin: &signer) {
        if (!exists<ChainRegistry>(ADMIN)) {
            move_to(admin, ChainRegistry { registry: vector::empty<Chain>() });
        };
        if (!exists<BlockTime>(ADMIN)) {
            move_to(admin, BlockTime { time: 0 });
        };
        if (!exists<ConfiguratorCap>(ADMIN)) {
            move_to(admin, ConfiguratorCap {});
        };
    }

    public entry fun register_chain(admin: &signer, id: u8, name: String, symbol: String) acquires ChainRegistry {
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);

        let chain_registry = borrow_global_mut<ChainRegistry>(ADMIN);
        let chain = Chain { id, name, symbol, validators: vector::empty<vector<u8>>() };
        vector::push_back(&mut chain_registry.registry, chain);
    }

    // in the future allow anyone to add validator if they stake enough coins
    public fun allow_validator(admin: &signer, chain_id: u8, validator: vector<u8>) acquires ChainRegistry {
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);

        let _cap = borrow_global<ConfiguratorCap>(signer::address_of(admin));

        let chain = find_and_return_chain(chain_id);
        let i = 0;
        let len = vector::length(&chain.validators);
        while (i < len) {
            let existing = vector::borrow(&chain.validators, i);
            assert!(*existing != validator, ERROR_VALIDATOR_IS_ALREADY_ALLOWED);
            i = i + 1;
        };
        vector::push_back(&mut chain.validators, validator);
    }


    public entry fun set_block_time(admin: &signer, new_time: u64) acquires BlockTime, ConfiguratorCap {
        assert!(exists<ConfiguratorCap>(signer::address_of(admin)), ERROR_NOT_ADMIN);

        let block_time_ref = borrow_global_mut<BlockTime>(ADMIN);
        block_time_ref.time = new_time;
    }

    fun find_and_return_chain(chain_id: u8): &mut Chain acquires ChainRegistry {
        let chain_registry = borrow_global_mut<ChainRegistry>(ADMIN);
        let len = vector::length(&chain_registry.registry);
        let i = 0;
        while (i < len) {
            let chain_ref = vector::borrow_mut(&mut chain_registry.registry, i);
            if (chain_ref.id == chain_id) {
                return chain_ref
            };
            i = i + 1;
        };
        abort(ERROR_INVALID_CHAIN_ID)
    }

    #[view]
    public fun get_full_chain_registry(): vector<Chain> acquires ChainRegistry {
        let reg = borrow_global<ChainRegistry>(ADMIN);
        reg.registry
    }

    #[view]
    public fun get_chain_by_ID(chain_id: u8): Chain acquires ChainRegistry {
        let chain_registry = borrow_global<ChainRegistry>(ADMIN);
        let len = vector::length(&chain_registry.registry);
        let i = 0;
        while (i < len) {
            let chain_ref = vector::borrow(&chain_registry.registry, i);
            if (chain_ref.id == chain_id) {
                return *chain_ref;
            };
            i = i + 1;
        };
        abort(ERROR_INVALID_CHAIN_ID)
    }

    #[view]
    public fun get_block_time(): u64 acquires BlockTime {
        let block_time = borrow_global<BlockTime>(ADMIN);
        block_time.time
    }

    public fun get_supra_bankers(): vector<address> {
        let chain = get_chain_by_ID(8);
        let len = vector::length(&chain.validators);
        let vect = vector::empty<address>();
        while (len > 0) {
            let validator = vector::borrow(&chain.validators, len-1);
            vector::push_back(&mut vect, from_bcs::to_address(validator));
            len = len - 1;
        };
        vect
    }
}
