module bridge_addr::bridge_core {
    use std::vector;
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_std::error;

    // --- CUSTOM SERIALIZATION CONSTANTS ---
    // User requirement: u256 from ZK should be treated as Little Endian bytes
    
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

    /// 1. MESSAGE EXECUTION (Settlement)
    /// This is permissionless: anyone can call it with a valid proof.
    public entry fun execute_update(
        _relayer: &signer,
        proof_a: vector<u8>,
        proof_b: vector<u8>, // Order: X.re, X.im, Y.re, Y.im
        proof_c: vector<u8>,
        public_signals: vector<u256> // [root, epoch, varID, newValue]
    ) acquires BridgeConfig, Variables {
        let config = borrow_global_mut<BridgeConfig>(@bridge_addr);
        
        // 1a. Security Anchor: Ensure proof was built against the current ON-CHAIN root
        let proof_root = *vector::borrow(&public_signals, 0);
        assert!(proof_root == config.current_validator_root, error::invalid_state(ERROR_STALE_ROOT));

        // 1b. Replay Protection: Ensure we don't process old or duplicate epochs
        let epoch = *vector::borrow(&public_signals, 1);
        assert!(epoch > config.last_processed_epoch, error::invalid_argument(ERROR_REPLAY));

        // 1c. Math Verification: The Groth16 Check
        // verify_proof_internal uses the hardcoded message_vk
        let is_valid = verify_proof_internal(proof_a, proof_b, proof_c, public_signals, config.message_vk);
        assert!(is_valid, error::invalid_argument(ERROR_INVALID_PROOF));

        // 1d. Final Settlement: Apply the state change
        let var_id = *vector::borrow(&public_signals, 2);
        let new_val = *vector::borrow(&public_signals, 3);
        
        let state = borrow_global_mut<Variables>(@bridge_addr);
        table::upsert(&mut state.map, var_id, u256_to_le_bytes(new_val));
        
        config.last_processed_epoch = epoch;
    }

    /// 2. TRUSTLESS VALIDATOR ROTATION
    /// This updates the root WITHOUT an admin. It requires a proof signed by OLD validators.
    public entry fun rotate_validators(
        _relayer: &signer,
        proof_a: vector<u8>,
        proof_b: vector<u8>,
        proof_c: vector<u8>,
        public_signals: vector<u256> // [oldRoot, newRoot, rotationEpoch]
    ) acquires BridgeConfig {
        let config = borrow_global_mut<BridgeConfig>(@bridge_addr);
        
        let old_root_in_proof = *vector::borrow(&public_signals, 0);
        let new_root = *vector::borrow(&public_signals, 1);
        
        // Ensure the rotation proof is authorizing a change FROM our current root
        assert!(old_root_in_proof == config.current_validator_root, error::invalid_state(ERROR_STALE_ROOT));

        // Verify rotation SNARK (proves 22/32 old validators signed the new root)
        let is_valid = verify_proof_internal(proof_a, proof_b, proof_c, public_signals, config.rotation_vk);
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
    ): bool;
}