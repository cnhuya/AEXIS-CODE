
module dev::QiaraZK_testV4 {
    use dev::QiaraZKV4::{Self as zk};
    use std::vector;
    use std::option;
    use aptos_std::bn254_algebra::{G1, G2, Gt, FormatG1Uncompr, FormatG2Uncompr, Fr, FormatFrLsb};
    use aptos_std::crypto_algebra::{Element, deserialize};

    fun tttta(number: u64){
        abort(number);
    }

    const VK_ALPHA_G1: vector<u8> = x"7e72740feabaf29959aca89e6b2ef66b0f59948256e681619508c8dd7f017624c5a97a75de48c96f855ed0179cbb939f72e0d1b1830267ca9f80a898dcb7f727";
    const VK_BETA_G2: vector<u8> = x"8d766fc183e9a6890da4d5e0822678bf29bf776522a54bb22605814ccc9fa72f393fa98453522b8b6d61864b65a383a44289e5639287c9c3662b8a3bd0296610fec2c747f6acb62e998afcebf40d1fdbf07bfc2fc1974d02ab7e47e640350d0b76f3c65fec8523521aa52e2030f2f75322e263a354ae21b94d2da31942b45c13";
    const VK_GAMMA_G2: vector<u8> = x"edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e19aa7dfa6601cce64c7bd3430c69e7d1e38f40cb8d8071ab4aeb6d8cdba55ec8125b9722d1dcdaac55f38eb37033314bbc95330c69ad999eec75f05f58d0890609";
    const VK_DELTA_G2: vector<u8> = x"9c77d6819e390ff1a5194361931e1b80ef74553b0f246feeb9c7233ca2dacd0dd78ae92d66415d608c2bc37bdc0acad110cc73af069a7ed024ce041baa75571b1b23e3659a3098f0c1059fb8c3a51228d099d2c403fa4904004605e5b1fff607150815879458a2ae04c74af65fc3e64db441789498a9d7c39c98c394f1e7ff02";

    const VK_IC_POINTS: vector<vector<u8>> = vector[
        x"76b96c90bf6be375f5f93337a44b3d3a4f8897363691492ef5f63c3907d28e06b6f1eeac1bf8f7a03fda930c4a5d011b547ad60f3f9b821d7478c977ec7b9e28",
        x"8ced23729e4291ac9f2de53bd8ec0f009b3009acc6c538cc3f655dd43d25ca0f24840da75044c5160b0bc36f951c17dd085cedf0d4636c553c773d65a6c94f00",
        x"14e05a3328e5d119e2c8ebc99e23be6b135ef55ea9dfb7a36b6b2ab162c46c0a9532d25ecd9a3decc0baa81384dc973485c85f811048c20da00de60fc3bfd702"
    ];

    //ignore this (unsued)
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

        //tttta(1);

        // Do the same for all VK elements
        let vk_alpha_g1 = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&vk_alpha_g1_bytes));
        let vk_beta_g2 = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&vk_beta_g2_bytes));
        let vk_gamma_g2 = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&vk_gamma_g2_bytes));
        let vk_delta_g2 = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&vk_delta_g2_bytes));
        //tttta(47);
        // Public input unwrap
        let public_input = option::destroy_some(deserialize<Fr, FormatFrLsb>(&public_inputs_bytes));
        let public_inputs_vec = vector[public_input];
        //tttta(7);
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

    //ignore this (unsued)
    public entry fun verify_with_hardcoded_vk(
        proof_a_bytes: vector<u8>,
        proof_b_bytes: vector<u8>,
        proof_c_bytes: vector<u8>,
        public_signals_bytes: vector<vector<u8>> 
    ) {
        // 1. Deserialize Proof
        let p_a = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&proof_a_bytes));
        let p_b = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&proof_b_bytes));
        let p_c = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&proof_c_bytes));

        // 2. Deserialize VK Constants
        let vk_a = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&VK_ALPHA_G1));
        let vk_b = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&VK_BETA_G2));
        let vk_g = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&VK_GAMMA_G2));
        let vk_d = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&VK_DELTA_G2));

        
        // 3. Loop and Deserialize all 37 IC Points
        let ic_elements = vector::empty<Element<G1>>();
        let i = 0;
        while (i < vector::length(&VK_IC_POINTS)) {
            vector::push_back(&mut ic_elements, option::destroy_some(deserialize<G1, FormatG1Uncompr>(vector::borrow(&VK_IC_POINTS, i))));
            i = i + 1;
        };

        // 4. Deserialize Public Signals (Fr)
        let pub_inputs = vector::empty<Element<Fr>>();
        let j = 0;
        while (j < vector::length(&public_signals_bytes)) {
            vector::push_back(&mut pub_inputs, option::destroy_some(deserialize<Fr, FormatFrLsb>(vector::borrow(&public_signals_bytes, j))));
            j = j + 1;
        };

        // 5. Verify
        let success = zk::verify_proof<G1, G2, Gt, Fr>(&vk_a, &vk_b, &vk_g, &vk_d, &ic_elements, &pub_inputs, &p_a, &p_b, &p_c);
        assert!(success, 100);
    }
public entry fun verify_with_hardcoded_vk2(
    proof_a_bytes: vector<u8>,
    proof_b_bytes: vector<u8>,
    proof_c_bytes: vector<u8>,
    public_signals_bytes: vector<u256>,
) {
    let pub_inputs = vector::empty<Element<Fr>>();
    let ic_elements = vector::empty<Element<G1>>(); 
    let i = 0;

    //tttta(1);
    // --- STEP 1: Process Signals (u256 to Fr) ---
    while (i < vector::length<u256>(&public_signals_bytes)) {
        let val = *vector::borrow<u256>(&public_signals_bytes, i);
        let raw_bytes = vector::empty<u8>();
        let temp_val = val;
        let j = 0;
      
        // BigInt to Little Endian bytes
        while (j < 32) {
            vector::push_back(&mut raw_bytes, ((temp_val & 0xFF) as u8));
            temp_val = temp_val >> 8;
            j = j + 1;
        };
        let fr_opt = deserialize<Fr, FormatFrLsb>(&raw_bytes);
        if (option::is_none(&fr_opt)) { abort 101 }; 
        vector::push_back(&mut pub_inputs, option::destroy_some(fr_opt));
        i = i + 1;
    };
   //tttta(2);

// --- STEP 2: Process Proof (With Unique Error Codes) ---
    let p_a_opt = deserialize<G1, FormatG1Uncompr>(&proof_a_bytes);
    if (option::is_none(&p_a_opt)) { abort 2001 }; 

    let p_b_opt = deserialize<G2, FormatG2Uncompr>(&proof_b_bytes);
    if (option::is_none(&p_b_opt)) { abort 2002 }; 

    let p_c_opt = deserialize<G1, FormatG1Uncompr>(&proof_c_bytes);
    if (option::is_none(&p_c_opt)) { abort 2003 };

    // --- STEP 2: Process Proof ---
    let p_a = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&proof_a_bytes));
    let p_b = option::destroy_some(deserialize<G2, FormatG2Uncompr>(&proof_b_bytes));
    let p_c = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&proof_c_bytes));
  // tttta(4);
    // --- STEP 3: Process VK Constants ---
    let vk_a = option::destroy_some(deserialize<G1, FormatG1Uncompr>(&VK_ALPHA_G1));
    
    let k = 0; 
    let ic_len = vector::length(&VK_IC_POINTS);
    while (k < ic_len) {
        let ic_opt = deserialize<G1, FormatG1Uncompr>(vector::borrow(&VK_IC_POINTS, k));
        vector::push_back(&mut ic_elements, option::destroy_some(ic_opt));
        k = k + 1;
    };

    // --- STEP 4: Verification ---
    let success = zk::verify_proof<G1, G2, Gt, Fr>(
        &vk_a, 
        &option::destroy_some(deserialize<G2, FormatG2Uncompr>(&VK_BETA_G2)), 
        &option::destroy_some(deserialize<G2, FormatG2Uncompr>(&VK_GAMMA_G2)), 
        &option::destroy_some(deserialize<G2, FormatG2Uncompr>(&VK_DELTA_G2)), 
        &ic_elements, 
        &pub_inputs, 
        &p_a, 
        &p_b, 
        &p_c
    );
    
    assert!(success, 400); 
}}