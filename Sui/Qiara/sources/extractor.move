module Qiara::QiaraExtractorV1 {
    use std::vector;
    use sui::address;

    const EInvalidInputLength: u64 = 400;
    const EValueOverflow: u64 = 401;
    /// Helper to extract a 32-byte chunk starting at a specific signal index
    /// Each signal is 32 bytes, so offset = index * 32
    fun extract_chunk(inputs: &vector<u8>, index: u64): vector<u8> {
        let mut chunk = vector::empty<u8>();
        let start = index * 32;
        assert!(vector::length(inputs) >= start + 32, EInvalidInputLength);
        
        let mut i = 0;
        while (i < 32) {
            vector::push_back(&mut chunk, *vector::borrow(inputs, start + i));
            i = i + 1;
        };
        chunk
    }

    /// Extract Nullifier (Signal Index 9)
    public fun extract_nullifier(inputs: &vector<u8>): vector<u8> {
        extract_chunk(inputs, 9)
    }

    /// Extract Amount (Signal Index 7)
    /// Returns the raw 32 bytes (u256)
    public fun extract_amount(inputs: &vector<u8>): u64 {
        let chunk = extract_chunk(inputs, 7); // returns vector<u8> of length 32
        
        // 1. Ensure the value fits in a u64. 
        // In a 32-byte big-endian U256, the first 24 bytes must be 0.
        let mut i = 0;
        while (i < 24) {
            assert!(*vector::borrow(&chunk, i) == 0, EValueOverflow);
            i = i + 1;
        };

        // 2. Convert the last 8 bytes to u64 (Big Endian)
        let mut val = 0u64;
        let mut j = 24;
        while (j < 32) {
            val = (val << 8) | (*vector::borrow(&chunk, j) as u64);
            j = j + 1;
        };
        
        val
    }

    /// Reconstruct Address from two chunks (EVM uint160 logic)
    /// user = (_pubSignals[2] << 128) | _pubSignals[1]
    public fun extract_user_address(inputs: &vector<u8>): address {
        let chunk_low = extract_chunk(inputs, 1);  // _pubSignals[1]
        let chunk_high = extract_chunk(inputs, 2); // _pubSignals[2]
        reconstruct_address(chunk_low, chunk_high)
    }

    /// vaultAddr = (_pubSignals[6] << 128) | _pubSignals[5]
    public fun extract_vault_address(inputs: &vector<u8>): address {
        let chunk_low = extract_chunk(inputs, 5);  // _pubSignals[5]
        let chunk_high = extract_chunk(inputs, 6); // _pubSignals[6]
        reconstruct_address(chunk_low, chunk_high)
    }

    /// Bitwise reconstruction: (High << 128) | Low
    /// Since we are dealing with bytes, we map the positions specifically.
    fun reconstruct_address(low: vector<u8>, high: vector<u8>): address {
        let mut addr_bytes = vector::empty<u8>();
        
        // Sui addresses are 32 bytes. EVM addresses are 20 bytes.
        // To match Solidity's address(uint160(...)), we take the lower 20 bytes 
        // of the combined result and pad the rest with 0s.
        
        // 1. We take the bytes from 'low' (Signal index 1/5) - typically 16 bytes
        // 2. We take the relevant bytes from 'high' (Signal index 2/6) - typically 4 bytes
        // 3. Pad the first 12 bytes with 0 for a standard 32-byte Sui Address format
        
        let mut i = 0;
        while (i < 12) { vector::push_back(&mut addr_bytes, 0); i = i + 1; };
        
        // Add the 4 bytes from high (the << 128 part)
        // Note: Logic assumes Big Endian from Arkworks/Bcs
        let mut j = 28;
        while (j < 32) {
            vector::push_back(&mut addr_bytes, *vector::borrow(&high, j));
            j = j + 1;
        };

        // Add the 16 bytes from low
        let mut k = 16;
        while (k < 32) {
            vector::push_back(&mut addr_bytes, *vector::borrow(&low, k));
            k = k + 1;
        };

        address::from_bytes(addr_bytes)
    }
}