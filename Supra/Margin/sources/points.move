module dev::QiaraPointsV1{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table::{Self, Table};

    use dev::QiaraTokenTypesV1::{Self as TokensType};
    use dev::QiaraChainTypesV1::{Self as ChainTypes};

    use dev::QiaraStorageV1::{Self as storage, Access as StorageAccess};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_USER_DID_NOT_INITIALIZE_HIS_RI_YET: u64 = 2;
    const ERROR_SOME_OF_REWARD_STRUCT_IS_NONE: u64 = 2;
    const ERROR_SOME_OF_INTEREST_STRUCT_IS_NONE: u64 = 3;

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

    struct User has store, key, copy {
        points: u256,
        perk: String,
    }
// === STRUCTS === //
    // (shared storage owner) -> points
    struct UsersProfile has key {
        points: Table<vector<u8>, User>,
    }

// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<UsersProfile>(@dev)) {
            move_to(admin,UsersProfile {points: table::new<vector<u8>, User>()});
        };

    }

// === ENTRY FUN === //

    public fun ensure_user(points_table: &mut UsersProfile, user: vector<u8>): &mut User{

        if (!table::contains(&points_table.points, user)) {
            table::add(&mut points_table.points, user, User {points: 0, perk: utf8(b"none")});
        };
        return table::borrow_mut(&mut points_table.points, user)
    }

    public fun add_points(user: vector<u8>, n_points: u256, perm: Permission) acquires UsersProfile{
        let user  = ensure_user(borrow_global_mut<UsersProfile>(@dev),user);
        user.points = user.points + n_points;
    }

    public fun remove_points(user: vector<u8>, n_points: u256, perm: Permission) acquires UsersProfile{
        let user  = ensure_user(borrow_global_mut<UsersProfile>(@dev),user);
        if(n_points > user.points){
            user.points = 0;
            return
        };
        user.points = user.points - n_points;
    }


// === PUBLIC VIEWS === //

    #[view]
    public fun get_user(user: vector<u8>): User acquires UsersProfile {
        let points_table = borrow_global<UsersProfile>(@dev);

        if (!table::contains(&points_table.points, user)) {
            return User {points: 0, perk: utf8(b"none")}
        };
        return *table::borrow(&points_table.points, user)
    }

    #[view]
    public fun simulate_xp(level: u256): u256{
        let xp_needed = 100_000_000;
        let levelX4 = level*level*level*level;

        return (xp_needed * levelX4)/1_000_000
    }

    #[view]
    public fun return_fee_points_conversion(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraPoints"), utf8(b"ANY_FEE_CONVERSION"))) as u256)
    }
    #[view]
    public fun return_perp_volume_points_conversion(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraPoints"), utf8(b"PERPS_VOLUME_CONVERSION"))) as u256)
    }
    #[view]
    public fun return_market_liquidity_provision_points_conversion(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraPoints"), utf8(b"MARKET_LIQUIDITY_PROVISION_CONVERSION"))) as u256)
    }
    #[view]
    public fun return_free_daily_claim_points(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraPoints"), utf8(b"DAILY_CLAIM"))) as u256)
    }

}
