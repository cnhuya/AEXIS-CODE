
module dev::QiaraZK_test {
    use dev::QiaraZK::{Self as zk};
    use std::vector;
    use std::option;
    use aptos_std::bn254_algebra::{G1, G2, Gt, FormatG1Uncompr, FormatG2Uncompr, Fr, FormatFrMsb};
    use aptos_std::crypto_algebra::{Element, deserialize};

    public entry fun verify_with_manual_vk(
        // Proof & Inputs
        proof_a_bytes: vector<u8>,
        proof_b_bytes: vector<u8>,
        proof_c_bytes: vector<u8>,
        public_inputs_bytes: vector<u8>, // This is your Root/Leaf data

        // Verification Key (The "vk" variables)
        vk_alpha_g1_bytes: vector<u8>,
        vk_beta_g2_bytes: vector<u8>,
        vk_gamma_g2_bytes: vector<u8>,
        vk_delta_g2_bytes: vector<u8>,
        vk_ic0_bytes: vector<u8>, // First part of IC (the "base")
        vk_ic1_bytes: vector<u8>  // Second part of IC (corresponds to Root)
    ) {
            // 1. Deserialize and Unwrap
        // Instead of: let proof_a = deserialize<G1, FormatG1Uncompr>(&proof_a_bytes);
        // Use:
        let proof_a = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&proof_a_bytes));
        let proof_b = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&proof_b_bytes));
        let proof_c = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&proof_c_bytes));

        // Do the same for all VK elements
        let vk_alpha_g1 = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&vk_alpha_g1_bytes));
        let vk_beta_g2 = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&vk_beta_g2_bytes));
        let vk_gamma_g2 = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&vk_gamma_g2_bytes));
        let vk_delta_g2 = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&vk_delta_g2_bytes));

        // Public input unwrap
        let public_input = option::destroy_some(deserialize<Fr, FormatFrMsb>(&public_inputs_bytes));
        let public_inputs_vec = vector[public_input];

        // IC points unwrap
        let vk_ic0 = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&vk_ic0_bytes));
        let vk_ic1 = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&vk_ic1_bytes));
        let vk_uvw_gamma_g1 = vector[vk_ic0, vk_ic1];

        // 2. NOW you can call verify_proof
        let success = zk::verify_proof<G1, G2, Gt, Fr>(
            &vk_alpha_g1,
            &vk_beta_g2,
            &vk_gamma_g2,
            &vk_delta_g2,
            &vk_uvw_gamma_g1,
            &public_inputs_vec,
            &proof_a,
            &proof_b,
            &proof_c
        );

        assert!(success, 100);
    }
}



   