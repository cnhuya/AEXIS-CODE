module 0x0::QIARA_ZKV1 {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::groth16;
    use std::bcs;
    use sui::table::{Self, Table};
    use std::string::{String};
    use std::vector;
    use sui::table::length;

    // Your VK here (keep as is for now)
    const FULL_VK: vector<u8> = x"27df2e301330e5d02b2186546a1b72d0fc5855fddada0ce8280624ac0fa997ae8ea6357a77da653500cc55e4d270793203568ec9db801ab2b7f2616faa85731030b0a5150c29b6590ba2592e21352963c05d51638e5afd249d8ae7fa2bd11427edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e19a65a865c9d06eb6935704d4f9188e8f9b690c9e97f944d904d658f592f702b2254fd0576c65caace81d484afbae54657485a5d1ef2ca3b1cc2e3b2e6cf5c4b2205000000000000006a81305b4e9e2e3f4491c55af33d21feb42d45e829173acaff84d798f1e1d18166be7c0e70882fbd01a223456916879efae8d2de4541db2093e67ac8e779a994561fff71ae8c744802b39f0b2159c49aaea47bfbce99ed5230fa02eb314c181b9f153687935a69c5a86157590087417fa01acc94b38648fc1a21650adc712c0a4d7152aa0254e589abb894cf7667b6d70136cbb7392917807d30e26f6fc28d10";
    const TEST_PROOF: vector<u8> = x"bb29263b323f468badcc2943436e31d8f42bb9104a543b45fa242fc5658408015c67a8347f69a3c2ed82ae801a8daf0e44bcbf27749ea86361b16313ad413d245b2f2a552f724f11c34cd48743648ff28aa3ac21b90abd1d3b56cbf0f751521dc32c1d78d9efb8fa87f061a89e4856407eae63456951befa78ba4986ff7a9b00";
    const TEST_PUBLIC: vector<u8> = x"7e74000000000000000000000000000000000000000000000000000000000000d594f8a4ae5ec21c31aeacc7d40082151c536c234699f45c618c3124ea40191c92b6c9ffcdccb90af906937ac35f30518e9314e71602eb3d142d23869eba710a0000000000000000000000000000000000000000000000000000000000000000";

    const EInvalidProof: u64 = 0;
    const EInvalidPublicInputs: u64 = 1;
    const ENullifierUsed: u64 = 2;
    const ERootAlreadyExists: u64 = 3;


    public struct State has key, store {
        id: UID,
        epoch: u64,
        root: vector<u8>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(State {
            id: object::new(ctx),
            epoch: 0,
            root: vector::empty(),
        });
    }

    public entry fun test_verify2(proof: vector<u8>, public_inputs: vector<u8>) {
        let curve = groth16::bn254();
        let pvk = groth16::prepare_verifying_key(&curve, &FULL_VK);

        let proof_points_struct = groth16::proof_points_from_bytes(proof);
        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);

        assert!(
            groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct),
            EInvalidProof
        );
    }

    public entry fun test_verify(){
        let curve = groth16::bn254();
        let pvk = groth16::prepare_verifying_key(&curve, &FULL_VK);

        let proof_points_struct = groth16::proof_points_from_bytes(TEST_PROOF);
        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(TEST_PUBLIC);
       // let proof_points_struct = groth16::proof_points_from_bytes(TEST_PROOF);

        assert!(
            groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct),
            EInvalidProof
        );
    }

    public entry fun verifyZK(
        state: &mut State,
        public_inputs: vector<u8>,
        proof_points: vector<u8>,
    ) {
        let curve = groth16::bn254();
        
        // Debug: Check VK size first
        assert!(vector::length(&FULL_VK) > 0, 100);
        
        let pvk = groth16::prepare_verifying_key(&curve, &FULL_VK);

        // Verify the proof
        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(
            groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct),
            EInvalidProof
        );

        // Extraction logic...
        assert!(vector::length(&public_inputs) >= 64, EInvalidPublicInputs);

        let epoch = extract_epoch_from_inputs(&public_inputs);
        let validator_root = extract_validator_root_from_inputs(&public_inputs);

        if(state.epoch == epoch) {
            abort ENullifierUsed; // Prevent re-using the same nullifier/epoch
        };

        if(state.root == validator_root) {
            abort ERootAlreadyExists; // Prevent re-using the same root
        };

        state.epoch = epoch;
        state.root = validator_root;

    }

    // ... rest of your functions

/// Extracts the first 8 bytes of the FOURTH scalar (index 3) as u64 (Little Endian)
    /// Offset starts at 32 * 3 = 96
    fun extract_epoch_from_inputs(inputs: &vector<u8>): u64 {
        let mut val: u64 = 0;
        let mut i = 0;
        let offset = 96; 
        while (i < 8) {
            // Borrow from the 4th 32-byte chunk
            let byte = *vector::borrow(inputs, offset + i);
            val = val | ((byte as u64) << ((8 * i) as u8));
            i = i + 1;
        };
        val
    }

    /// Extracts the full second 32-byte scalar (index 1) as a vector<u8>
    /// Offset starts at 32 * 1 = 32
    fun extract_validator_root_from_inputs(inputs: &vector<u8>): vector<u8> {
        let mut root = vector::empty<u8>();
        let mut i = 32; // Start at the beginning of the second 32-byte block
        while (i < 64) {
            vector::push_back(&mut root, *vector::borrow(inputs, i));
            i = i + 1;
        };
        root
    }

}