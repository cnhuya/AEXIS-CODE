module Qiara::QiaraExtractorV1 {
    use std::vector;
    use std::string::{Self, String};
    use sui::address;
    use sui::poseidon;

    // --- Constants ---
    const E_INVALID_CHAIN_ID: u64 = 0;
    const E_INVALID_INPUT_LENGTH: u64 = 400;
    const E_VALUE_OVERFLOW: u64 = 401;

    const BN254_MAX: u256 = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    
    /// Unpacked Slot 8: chainID(32) + amount(64) + index(64) + nonce(64)
    public struct UnpackedTx has drop {
        chain_id: u64,
        amount: u64,
        nonce: u64
    }

 // --- Public Extraction API ---
    /// Extracts and unpacks the metadata from the 8th public signal (index 7)
    public fun extract_chain_id(inputs: &vector<u8>): u64 {
        let packed_bytes = extract_chunk(inputs, 7);
        unpack_slot_8(bytes_to_u256(packed_bytes)).chain_id
    }
    public fun extract_amount(inputs: &vector<u8>): u64 {
        let packed_bytes = extract_chunk(inputs, 7);
        unpack_slot_8(bytes_to_u256(packed_bytes)).amount
    }
    public fun extract_nonce(inputs: &vector<u8>): u64 {
        let packed_bytes = extract_chunk(inputs, 7);
        unpack_slot_8(bytes_to_u256(packed_bytes)).nonce
    }

    /// Reconstructs the User Address from signals 3 and 4
    public fun extract_user_address(inputs: &vector<u8>): address {
        // Assuming chunk 4 is High (first 16 bytes) and chunk 3 is Low (last 16 bytes)
        let low_bytes = extract_chunk(inputs, 3); 
        let high_bytes = extract_chunk(inputs, 4);
        reconstruct_address(low_bytes, high_bytes)
    }

    /// Extracts human-readable Storage ID (index 5)
    public fun extract_token(inputs: &vector<u8>): String {
        u256_to_string(bytes_to_u256(extract_chunk(inputs, 5)))
    }

    /// Extracts human-readable Vault Name (index 6)
    public fun extract_provider(inputs: &vector<u8>): String {
        u256_to_string(bytes_to_u256(extract_chunk(inputs, 6)))
    }

    /// Builds a Nullifier using Poseidon(user_low, user_high, nonce)
    public fun build_nullifier(inputs: &vector<u8>): u256 {
        // Extract signals using indices 3, 4 (Address) and 7 (Packed Data for Nonce)
        let user_l_bytes = extract_chunk(inputs, 3);
        let user_h_bytes = extract_chunk(inputs, 4);
        
        let user_l = bytes_to_u256(user_l_bytes);
        let user_h = bytes_to_u256(user_h_bytes);
        let nonce = (extract_nonce(inputs) as u256);

        // CRITICAL CHECK: Ensure inputs are within the BN254 Range
        // If they aren't, it means the signals were packed differently 
        // or the Big Endian conversion resulted in a value > BN254_MAX
        let field_l = user_l % BN254_MAX;
        let field_h = user_h % BN254_MAX;

        let mut data = vector::empty<u256>();
        vector::push_back(&mut data, field_l);
        vector::push_back(&mut data, field_h);
        vector::push_back(&mut data, nonce);

        poseidon::poseidon_bn254(&data)
    }

    // --- Internal Bit Shifting & Unpacking ---

    fun unpack_slot_8(packed_data: u256): UnpackedTx {
        UnpackedTx {
            chain_id: ((packed_data) & 0xFFFFFFFF) as u64,
            amount:   ((packed_data >> 32) & 0xFFFFFFFFFFFFFFFF) as u64,
            nonce:    ((packed_data >> 96) & 0xFFFFFFFFFFFFFFFF) as u64,
        }
    }

    fun reconstruct_address(low: vector<u8>, high: vector<u8>): address {
        let mut addr_bytes = vector::empty<u8>();
        
        // Step 1: Get the 16 data bytes from the High Field Element (Indices 16-31)
        let mut i = 16;
        while (i < 32) {
            vector::push_back(&mut addr_bytes, *vector::borrow(&high, i));
            i = i + 1;
        };

        // Step 2: Get the 16 data bytes from the Low Field Element (Indices 16-31)
        let mut j = 16;
        while (j < 32) {
            vector::push_back(&mut addr_bytes, *vector::borrow(&low, j));
            j = j + 1;
        };

        // Now addr_bytes is exactly 32 bytes: [High_16_bytes] + [Low_16_bytes]
        address::from_bytes(addr_bytes)
    }

    // --- Core Conversion Utilities ---

    fun extract_chunk(inputs: &vector<u8>, index: u64): vector<u8> {
        let start = index * 32;
        assert!(vector::length(inputs) >= start + 32, E_INVALID_INPUT_LENGTH);
        
        let mut chunk = vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            vector::push_back(&mut chunk, *vector::borrow(inputs, start + i));
            i = i + 1;
        };
        chunk
    }

public fun bytes_to_u256(bytes: vector<u8>): u256 {
    let mut res: u256 = 0;
    let mut i = 32; // Start from the end
    while (i > 0) {
        i = i - 1;
        res = (res << 8) | (*vector::borrow(&bytes, i) as u256);
    };
    res
}

public fun u256_to_string(value: u256): String {
    let mut bytes = vector::empty<u8>();
    let mut temp = value;
    let mut i = 0;
    
    while (i < 32) {
        // Extract the high byte
        let byte = ((temp >> 248) & 0xFF) as u8;
        
        // Only push non-null bytes (skip padding)
        if (byte != 0) { 
            vector::push_back(&mut bytes, byte); 
        };
        
        temp = temp << 8;
        i = i + 1;
    };

    // Convert the vector of bytes directly into a UTF-8 String
    string::utf8(bytes)
}}