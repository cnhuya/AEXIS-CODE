module dev::QiaraStakingThirdPartyV2{
    use std::string::{Self, utf8};
    use dev::QiaraStorageV34::{Self as storage};

// === VIEW FUNCTIONS === //
    #[view]
    public fun return_unlock_period(): u64 {
      storage::expect_u64(storage::viewConstant(utf8(b"QiaraStaking"), utf8(b"UNLOCK_PERIOD")))
    }

    #[view]
    public fun return_base_weight(): u64 {
      storage::expect_u64(storage::viewConstant(utf8(b"QiaraStaking"), utf8(b"BASE_WEIGHT")))
    }
      
    #[view]
    public fun return_efficiency_slashing(): u64 {
      storage::expect_u64(storage::viewConstant(utf8(b"QiaraStaking"), utf8(b"TIER_DEEFICIENCY")))
    }

    #[view]
    public fun return_staking_fee(): u64 {
      storage::expect_u64(storage::viewConstant(utf8(b"QiaraStaking"), utf8(b"STAKING_FEE")))
    }

}
