module dev::QiaraHelperV3 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;

    use dev::QiaraCoinTypesV5::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use supra_framework::supra_coin::{Self, SupraCoin};

    use dev::QiaraStorageV22::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV22::{Self as capabilities, Access as CapabilitiesAccess};

    use dev::QiaraVaultsV11::{Self as Market, Vault};

    use dev::QiaraVerifiedTokensV8::{Self as VerifiedTokens, Metadata, Tier};

    struct Governance has copy, drop{
        minimum_tokens_to_propose: u64,
        proposal_burn_fee: u64,
        quarum_to_pass: u64,
        minimum_votes: u64,
        scale: u64,
    }

    struct Vaults has drop{
        tier: Tier,
        metadata: Metadata,
        vaults: vector<Vault>,
    }


    #[view]
    public fun viewVaults(): vector<Vaults> {
        let tokens = VerifiedTokens::get_registered_vaults();
        let len = vector::length(&tokens);
        let vect = vector::empty<Vaults>();
        while(len>0){
            let metadata = vector::borrow(&tokens, len-1);
            let tier = VerifiedTokens::get_tier(VerifiedTokens::get_coin_metadata_tier(metadata));
            vector::push_back(&mut vect, Vaults {tier: tier, metadata: VerifiedTokens::get_coin_metadata_by_res(VerifiedTokens::get_coin_metadata_resource(metadata)), vaults: Market::get_vault_providers(VerifiedTokens::get_coin_metadata_resource(metadata))});
            len = len-1;
        };
        return vect
    }

    #[view]
    public fun viewGovernance(): Governance {
        Governance {
            minimum_tokens_to_propose: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"))),
            proposal_burn_fee: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"BURN_TAX"))),
            quarum_to_pass: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"))),
            minimum_votes: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"))),
            scale: 100_000_000,
        }
    }
}
