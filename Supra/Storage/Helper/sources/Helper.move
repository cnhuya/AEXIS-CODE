module dev::QiaraHelperV1 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;

    use dev::QiaraStorageV13::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV13::{Self as capabilities, Access as CapabilitiesAccess};

    struct Governance has copy, drop{
        minimum_tokens_to_propose: u64,
        proposal_burn_fee: u64,
        quarum_to_pass: u64,
        minimum_votes: u64,
        scale: u64,
    }

    #[view]
    public fun viewGovernance(): Governance acquires KeyRegistry {
        Governance {
            minimum_tokens_to_propose: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"))),
            proposal_burn_fee: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"BURN_TAX"))),
            quarum_to_pass: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"))),
            minimum_votes: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"))),
            scale: 100_000_000,
        }
    }
}
