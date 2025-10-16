module dev::QiaraHelperV11 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;

    use dev::QiaraCoinTypesV9::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use supra_framework::supra_coin::{Self, SupraCoin};

    use dev::QiaraStorageV24::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV24::{Self as capabilities, Access as CapabilitiesAccess};
    use dev::QiaraVaultTypesV9::{Self as VaultTypes};
    use dev::QiaraVaultsV21::{Self as Market, Vault};

    use dev::QiaraMathV9::{Self as QiaraMath};

    use dev::QiaraVerifiedTokensV18::{Self as VerifiedTokens, Metadata, Tier};

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
        vaults: vector<FullVault>,
    }


    struct FullVault has key, store, copy, drop{
        provider: String,
        total_deposited: u128,
        total_borrowed: u128,
        utilization: u64,
        lend_rate: u256,
        borrow_rate: u256
    }

    #[view]
    public fun viewVaults(): vector<Vaults> {
        let tokens = VerifiedTokens::get_registered_vaults();
        let len = vector::length(&tokens);
        let vect = vector::empty<Vaults>();

        let i = 0;
        while (i < len) {
            let metadata = vector::borrow(&tokens, i);

            // get vault identifier
            let vault_res = VerifiedTokens::get_coin_metadata_resource(metadata);

            // fetch vault totals
            let (providers, total_deposits, total_borrows) = Market::get_full_vault(vault_res);

            // collect all FullVaults for this metadata
            let vaults_ = vector::empty<FullVault>();

            let j = 0;
            let vault_count = vector::length(&providers);
            while (j < vault_count) {
                let provider = *vector::borrow(&providers, j);
                let deposited = *vector::borrow(&total_deposits, j);
                let borrowed = *vector::borrow(&total_borrows, j);
                let utilization = Market::get_utilization_ratio(deposited, borrowed);
                //abort(VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate(vault_res)) as u64); // 5774
                //abort((utilization) as u64); // 0
                //abort((VerifiedTokens::rate_scale(VerifiedTokens::get_coin_metadata_tier(metadata), true)) as u64); // 3000
                let (lend_apy, _, _) = QiaraMath::compute_rate(
                    (VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate(vault_res)) as u256),
                    ((utilization+1) as u256),
                    ((VerifiedTokens::rate_scale(VerifiedTokens::get_coin_metadata_tier(metadata), true)) as u256),
                    true,
                    5
                );
                let (borrow_apy, _, _) = QiaraMath::compute_rate(
                    (VaultTypes::get_vault_lend_rate(VaultTypes::get_vault_rate(vault_res)) as u256),
                    ((utilization+1) as u256),
                    ((VerifiedTokens::rate_scale(VerifiedTokens::get_coin_metadata_tier(metadata), false)) as u256),
                    false,
                    5
                );
            //  abort(01);
                vector::push_back(
                    &mut vaults_,
                    FullVault {
                        provider: provider,
                        total_deposited: deposited,
                        total_borrowed: borrowed,
                        utilization: utilization,
                        lend_rate: lend_apy,
                        borrow_rate: borrow_apy
                    }
                );
            // abort(001);
                j = j + 1;
            };

            // push Vaults entry with all providers for this token
            vector::push_back(
                &mut vect,
                Vaults {
                    tier: VerifiedTokens::get_tier(VerifiedTokens::get_coin_metadata_tier(metadata)),
                    metadata: VerifiedTokens::get_coin_metadata_by_res(vault_res),
                    vaults: vaults_
                }
            );

            i = i + 1;
        };

        vect
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
