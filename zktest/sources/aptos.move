module dev::bridge_coreV7 {
    use std::vector;
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_std::error;
    use dev::groth16v1::{Self as groth16};
    use std::option;
    use aptos_std::bn254_algebra::{G1, G2, Gt, FormatG1Uncompr, FormatG2Uncompr, Fr, FormatFrLsb};
    use aptos_std::crypto_algebra::{Element, deserialize};
    // --- CUSTOM SERIALIZATION CONSTANTS ---
    // User requirement: u256 from ZK should be treated as Little Endian bytes
    
    const VK_ALPHA_G1: vector<u8> = x"27df2e301330e5d02b2186546a1b72d0fc5855fddada0ce8280624ac0fa9972e510e88b18f6d6bb89d883ef1e891d10c15f1286f6d72468c3492f0d211433b29";
    const VK_BETA_G2: vector<u8> = x"8ea6357a77da653500cc55e4d270793203568ec9db801ab2b7f2616faa85731030b0a5150c29b6590ba2592e21352963c05d51638e5afd249d8ae7fa2bd11427ffccc74af894865c627316c077925a00df831b3896ec55973deb89b1769d9815c92193e43b805821e6af673a482d63532bf74a043c08c643ce155cdf2c727410";
    const VK_GAMMA_G2: vector<u8> = x"edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e19aa7dfa6601cce64c7bd3430c69e7d1e38f40cb8d8071ab4aeb6d8cdba55ec8125b9722d1dcdaac55f38eb37033314bbc95330c69ad999eec75f05f58d0890609";
    const VK_DELTA_G2: vector<u8> = x"a65a865c9d06eb6935704d4f9188e8f9b690c9e97f944d904d658f592f702b2254fd0576c65caace81d484afbae54657485a5d1ef2ca3b1cc2e3b2e6cf5c4b225b7b27679d8deee39e7db32739984a8ba3e4113ff58c4526e21ee58e81dd8a2c74543a2f50bb698ee42c9f15f3f0e8e4fdf8f174c4bc8794db2ef26ee56d7204";
    
    const VK_IC_POINTS: vector<vector<u8>> = vector[
        x"6a81305b4e9e2e3f4491c55af33d21feb42d45e829173acaff84d798f1e1d101cba7a56fdc0574ee85cd54add152db6001684b188ae3c321e0ab2098318ea426",
        x"66be7c0e70882fbd01a223456916879efae8d2de4541db2093e67ac8e779a914062f16d47e46e670214c6ef9f6f3d13929d00b3ee91bec11333867865716e11e",
        x"561fff71ae8c744802b39f0b2159c49aaea47bfbce99ed5230fa02eb314c181b495089ea7aa23be671f53511f0f9caa8abc2414260fd9ad08d5dc74cf258ea02",
        x"9f153687935a69c5a86157590087417fa01acc94b38648fc1a21650adc712c0ac396d59f91a7ed88b2acc5193ac16a361a231829d54d3a8f3b91aa1cf0fc5216",
        x"4d7152aa0254e589abb894cf7667b6d70136cbb7392917807d30e26f6fc28d100382cdfdbac49624ecf698c4c05eda612e47029c264030ccc2f7af00cbeda613"
    ];

    struct BridgeConfig has key {
        current_validator_root: u256,
        last_processed_epoch: u64,
        // The Verification Key (VK) for Message updates
        message_vk: vector<u8>,
        // The Verification Key (VK) for Validator Rotations
        rotation_vk: vector<u8>,
    }

    struct Variables has key {
        map: Table<u256, vector<u8>>,
    }

    const ERROR_UNAUTHORIZED: u64 = 1;
    const ERROR_INVALID_PROOF: u64 = 2;
    const ERROR_STALE_ROOT: u64 = 3;
    const ERROR_REPLAY: u64 = 4;


public entry fun verify_with_hardcoded_vk2(
    proof_a_bytes: vector<u8>,
    proof_b_bytes: vector<u8>,
    proof_c_bytes: vector<u8>,
    public_signals_bytes: vector<u256>,
) {
    let pub_inputs = vector::empty<Element<Fr>>();
    let ic_elements = vector::empty<Element<G1>>(); 
    let i = 0;

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
    let success = groth16::verify_proof<G1, G2, Gt, Fr>(
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
}

    /// 1. MESSAGE EXECUTION (Settlement)
    /// This is permissionless: anyone can call it with a valid proof.
    /*public entry fun execute_update(
        _relayer: &signer,
        proof_a: vector<u8>,
        proof_b: vector<u8>, // Order: X.re, X.im, Y.re, Y.im
        proof_c: vector<u8>,
        public_signals: vector<u256> // [root, epoch, varID, newValue]
    ) acquires BridgeConfig, Variables {
        let config = borrow_global_mut<BridgeConfig>(@dev);
        
        // 1a. Security Anchor: Ensure proof was built against the current ON-CHAIN root
        let proof_root = *vector::borrow(&public_signals, 0);
        assert!(proof_root == config.current_validator_root, error::invalid_state(ERROR_STALE_ROOT));

        // 1b. Replay Protection: Ensure we don't process old or duplicate epochs
        let epoch = *vector::borrow(&public_signals, 1);
        assert!(epoch > (config.last_processed_epoch as u256), error::invalid_argument(ERROR_REPLAY));

        // 1c. Math Verification: The Groth16 Check
        // verify_proof_internal uses the hardcoded message_vk
        let is_valid = verify_proof_internal(proof_a, proof_b, proof_c, public_signals, config.message_vk);
        assert!(is_valid, error::invalid_argument(ERROR_INVALID_PROOF));

        // 1d. Final Settlement: Apply the state change
        let var_id = *vector::borrow(&public_signals, 2);
        let new_val = *vector::borrow(&public_signals, 3);
        
        let state = borrow_global_mut<Variables>(@dev);
        table::upsert(&mut state.map, var_id, u256_to_le_bytes(new_val));
        
        config.last_processed_epoch = ( epoch as u64 );
    }*/

    /// 2. TRUSTLESS VALIDATOR ROTATION
    /// This updates the root WITHOUT an admin. It requires a proof signed by OLD validators.
    /*public entry fun rotate_validators(
        _relayer: &signer,
        proof_a: vector<u8>,
        proof_b: vector<u8>,
        proof_c: vector<u8>,
        public_signals: vector<vector<u8>> // [oldRoot, newRoot, rotationEpoch]
    ) acquires BridgeConfig {
        let config = borrow_global_mut<BridgeConfig>(@dev);
        
        let old_root_in_proof = *vector::borrow(&public_signals, 0);
        let new_root = *vector::borrow(&public_signals, 1);
        
        // Ensure the rotation proof is authorizing a change FROM our current root
        assert!(old_root_in_proof == config.current_validator_root, error::invalid_state(ERROR_STALE_ROOT));
        
        // Verify rotation SNARK (proves 22/32 old validators signed the new root)
        let is_valid = groth16::verify_proof( vk_alpha_g1, vk_beta_g2, vk_gamma_g2, vk_delta_g2, vk_uvw_gamma_g1, public_signals, proof_a, proof_b, proof_c);
        assert!(is_valid, error::invalid_argument(ERROR_INVALID_PROOF));

        // HANDOVER: Update the security anchor
        config.current_validator_root = new_root;
    }

    // --- HELPER: LITTLE ENDIAN CONVERSION ---
    // Maps your JS 'to32Bytes' logic back into Aptos Move
    fun u256_to_le_bytes(value: u256): vector<u8> {
        let bytes = vector::empty<u8>();
        let temp = value;
        let i = 0;
        while (i < 32) {
            vector::push_back(&mut bytes, ((temp & 0xFF) as u8));
            temp = temp >> 8;
            i = i + 1;
        };
        bytes
    }

    native fun verify_proof_internal(
        pa: vector<u8>, pb: vector<u8>, pc: vector<u8>, signals: vector<u256>, vk: vector<u8>
    ): bool;*/
}