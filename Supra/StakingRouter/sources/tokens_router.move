module dev::QiaraStakingRouterV1 {
    use std::type_info::{Self, TypeInfo};
    use std::bcs;
    use std::string::{Self as String, String, utf8};

    use dev::QiaraMarginV3::{Self as Margin};

// === HELPER FUNCTIONS === //
    #[view]
    public fun get_total_staked(shared_storage_name:String): u256 {
        let (_, _, _, _, _, _, _, _, vote_weight, _, _) = Margin::get_user_total_usd(shared_storage_name);
        return vote_weight
    }

}
