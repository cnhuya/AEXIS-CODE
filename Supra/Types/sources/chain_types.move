module dev::QiaraChainTypesV18 {
    use std::string::{Self as string, String, utf8};


// === ERRORS === //
    const ERROR_INVALID_CHAIN: u64 = 1;

// === CONSTANTS === //
    const CHAIN_SUPRA: u8 = 1;
    const CHAIN_SUI: u8 = 2;
    const CHAIN_BASE: u8 = 3;
    const CHAIN_INJECTIVE: u8 = 4;
    const CHAIN_SOLANA: u8 = 5;

// === FUNCTIONS === //
    #[view]
    public fun return_all_chain_types(): vector<String> {
        vector[
            utf8(b"Supra"),
            utf8(b"Sui"), 
            utf8(b"Base"),
            utf8(b"Injective"),
            utf8(b"Solana")
        ]
    }
    #[view]
    public fun return_all_chain_ids(): vector<u8> {
        vector[CHAIN_SUPRA, CHAIN_SUI, CHAIN_BASE, CHAIN_INJECTIVE, CHAIN_SOLANA]
    }

    public fun convert_chain_type_to_string(id: u8): String {
        if (id == CHAIN_SUPRA) {
            utf8(b"Supra")
        } else if (id == CHAIN_SUI) {
            utf8(b"Sui")  // Fixed: was "Supra"
        } else if (id == CHAIN_BASE) {
            utf8(b"Base")
        } else if (id == CHAIN_INJECTIVE) {
            utf8(b"Injective")
        } else if (id == CHAIN_SOLANA) {
            utf8(b"Solana")
        } else {
            utf8(b"Unknown")
        }
        // Don't call ensure_valid_chain here - "Unknown" is valid output for invalid IDs
    }

    public fun convert_string_to_chain_type(chain: &String): u8 {
        if (chain == &utf8(b"Supra")) {
            CHAIN_SUPRA
        } else if (chain == &utf8(b"Sui")) {
            CHAIN_SUI
        } else if (chain == &utf8(b"Base")) {
            CHAIN_BASE
        } else if (chain == &utf8(b"Injective")) {
            CHAIN_INJECTIVE
        } else if (chain == &utf8(b"Solana")) {
            CHAIN_SOLANA
        } else {
            abort(ERROR_INVALID_CHAIN)  // Better than returning 0
        }
    }

    public fun ensure_valid_chain_id(chain_id: u8) {
        assert!(
            chain_id == CHAIN_SUPRA ||
            chain_id == CHAIN_SUI ||
            chain_id == CHAIN_BASE || 
            chain_id == CHAIN_INJECTIVE ||
            chain_id == CHAIN_SOLANA,
            ERROR_INVALID_CHAIN
        )
    }

    public fun ensure_valid_chain_name(chain: &String) {
        assert!(
            chain == &utf8(b"Supra") ||
            chain == &utf8(b"Sui") ||
            chain == &utf8(b"Base") ||
            chain == &utf8(b"Injective") ||
            chain == &utf8(b"Solana"),
            ERROR_INVALID_CHAIN
        )
    }
}
