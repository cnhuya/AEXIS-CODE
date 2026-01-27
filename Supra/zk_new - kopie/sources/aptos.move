module 0x0::QIARA_ZKV1 {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::groth16;
    use std::bcs;
    use sui::table::{Self, Table};
    use std::string::{String};
    use std::vector;

    // --- Your Provided Constants ---
    const VK_ALPHA_G1: vector<u8> = x"27df2e301330e5d02b2186546a1b72d0fc5855fddada0ce8280624ac0fa9972e510e88b18f6d6bb89d883ef1e891d10c15f1286f6d72468c3492f0d211433b29";
    const VK_BETA_G2: vector<u8> = x"8ea6357a77da653500cc55e4d270793203568ec9db801ab2b7f2616faa85731030b0a5150c29b6590ba2592e21352963c05d51638e5afd249d8ae7fa2bd11427ffccc74af894865c627316c077925a00df831b3896ec55973deb89b1769d9815c92193e43b805821e6af673a482d63532bf74a043c08c643ce155cdf2c727410";
    const VK_GAMMA_G2: vector<u8> = x"edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e19aa7dfa6601cce64c7bd3430c69e7d1e38f40cb8d8071ab4aeb6d8cdba55ec8125b9722d1dcdaac55f38eb37033314bbc95330c69ad999eec75f05f58d0890609";
    const VK_DELTA_G2: vector<u8> = x"a65a865c9d06eb6935704d4f9188e8f9b690c9e97f944d904d658f592f702b2254fd0576c65caace81d484afbae54657485a5d1ef2ca3b1cc2e3b2e6cf5c4b225b7b27679d8deee39e7db32739984a8ba3e4113ff58c4526e21ee58e81dd8a2c74543a2f50bb698ee42c9f15f3f0e8e4fdf8f174c4bc8794db2ef26ee56d7204";
    
    // We will concatenate these into a single vector for the PVK
    const VK_IC_POINTS: vector<vector<u8>> = vector[
        x"6a81305b4e9e2e3f4491c55af33d21feb42d45e829173acaff84d798f1e1d101cba7a56fdc0574ee85cd54add152db6001684b188ae3c321e0ab2098318ea426",
        x"66be7c0e70882fbd01a223456916879efae8d2de4541db2093e67ac8e779a914062f16d47e46e670214c6ef9f6f3d13929d00b3ee91bec11333867865716e11e",
        x"561fff71ae8c744802b39f0b2159c49aaea47bfbce99ed5230fa02eb314c181b495089ea7aa23be671f53511f0f9caa8abc2414260fd9ad08d5dc74cf258ea02",
        x"9f153687935a69c5a86157590087417fa01acc94b38648fc1a21650adc712c0ac396d59f91a7ed88b2acc5193ac16a361a231829d54d3a8f3b91aa1cf0fc5216",
        x"4d7152aa0254e589abb894cf7667b6d70136cbb7392917807d30e26f6fc28d100382cdfdbac49624ecf698c4c05eda612e47029c264030ccc2f7af00cbeda613"
    ];

    const EInvalidProof: u64 = 0;

    public struct Storage has key, store {
        id: UID,
        roots: Table<u64, String>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Storage {
            id: object::new(ctx),
            roots: table::new(ctx),
        });
    }

    /// Verifies using pvk_from_bytes logic
    public entry fun verifyZK(
        storage: &mut Storage,
        public_inputs: vector<u8>,
        proof_points: vector<u8>,
        root_str: String,
    ) {
        let curve = groth16::bn254();

        // 1. Manually assemble the IC points into one vector
        let mut vk_gamma_abc_g1 = vector::empty<u8>();
        let mut i = 0;
        while (i < vector::length(&VK_IC_POINTS)) {
            vector::append(&mut vk_gamma_abc_g1, *vector::borrow(&VK_IC_POINTS, i));
            i = i + 1;
        };

        // 2. We still need to use prepare_verifying_key because Sui's 
        // PreparedVerifyingKey components (gamma_g2_neg_pc_bytes) are NOT raw G2 points.
        // They are pre-processed for pairing. 
        // So we build the full VK vector and let the native function process it.
        
        let mut full_vk = vector::empty<u8>();
        vector::append(&mut full_vk, VK_ALPHA_G1);
        vector::append(&mut full_vk, VK_BETA_G2);
        vector::append(&mut full_vk, VK_GAMMA_G2);
        vector::append(&mut full_vk, VK_DELTA_G2);
        
        // Add number of IC points (as u32, Little Endian)
        let ic_len = (vector::length(&VK_IC_POINTS) as u32);
        vector::append(&mut full_vk, bcs::to_bytes(&ic_len));
        vector::append(&mut full_vk, vk_gamma_abc_g1);

        let pvk = groth16::prepare_verifying_key(&curve, &full_vk);

        // 3. Alternatively, if you HAD the precomputed bytes, you would call:
        // let pvk = groth16::pvk_from_bytes(vk_gamma_abc_g1, alpha_beta_pairing, gamma_neg, delta_neg);

        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        let verified = groth16::verify_groth16_proof(
            &curve,
            &pvk,
            &public_inputs_struct,
            &proof_points_struct
        );

        assert!(verified, EInvalidProof);

        // Extract Epoch (first scalar = first 32 bytes)
        let epoch = extract_epoch_from_inputs(&public_inputs);

        if (table::contains(&storage.roots, epoch)) {
            *table::borrow_mut(&mut storage.roots, epoch) = root_str;
        } else {
            table::add(&mut storage.roots, epoch, root_str);
        };
    }

    fun extract_epoch_from_inputs(inputs: &vector<u8>): u64 {
        let mut val: u64 = 0;
        let mut i = 0;
        while (i < 8) {
            let byte = *vector::borrow(inputs, i);
            val = val | ((byte as u64) << ((8 * i) as u8));
            i = i + 1;
        };
        val
    }

    public fun get_epoch(storage: &Storage): String{
        let current_epoch = table::length(&storage.roots) - 1;
        *table::borrow(&storage.roots, current_epoch)
    }

    public fun return_current_root(storage: &Storage, epoch: u64): String {
        *table::borrow(&storage.roots, epoch)
    }
}