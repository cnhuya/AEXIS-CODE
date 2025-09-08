module dev::AexisBridgeConfigV47 {
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::timestamp;
    use supra_framework::event;

    const ADMIN: address = @dev;   // replace with real admin address

    const ERROR_NOT_ADMIN: u64 = 1;

    struct Config has copy, drop, store, key {
        block_time: u64,
        quorum: u8,
    }

    #[event]
    struct ConfigChange has copy, drop, store {
        old_config: Config,
        new_config: Config,
    }

    /// Initialize config under admin signer
    fun init_module(admin: &signer)  {
        init_config(admin, 100, 2);
    }

    public fun init_config(admin: &signer, block_time: u64, quorum: u8)   {
        if (!exists<Config>(signer::address_of(admin))) {
            move_to(admin, Config { block_time: block_time, quorum: quorum });
        };
    }

    /// Change config (only ADMIN)
    public entry fun change_config(admin: &signer, block_time: u64, quorum: u8) acquires Config {
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);

        let config_ref = borrow_global_mut<Config>(ADMIN);
        let old_config = *config_ref;

        config_ref.block_time = block_time;
        config_ref.quorum = quorum;

        event::emit(ConfigChange {
            old_config,
            new_config: *config_ref,
        });
    }

    /// View config
    #[view]
    public fun view_config(): Config acquires Config {
        *borrow_global<Config>(ADMIN)
    }

    /// Days since epoch
    #[view]
    public fun get_epoch(): u64 {
        timestamp::now_seconds() / 86400
    }

    /// Get quorum
    public fun get_quorum(): u8 acquires Config {
        let config = borrow_global<Config>(ADMIN);
        config.quorum
    }

    /// Get block time
    public fun get_block_time(): u64 acquires Config {
        let config = borrow_global<Config>(ADMIN);
        config.block_time
    }
}
