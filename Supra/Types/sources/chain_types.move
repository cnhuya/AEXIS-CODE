module dev::QiaraChainTypesV17 {
    use std::string::{Self as string, String, utf8};

    const CHAIN_SUPRA: u8 = 1;
    const CHAIN_SUI: u8 = 2;
    const CHAIN_BASE: u8 = 3;
    const CHAIN_INJECTIVE: u8 = 4;
    const CHAIN_SOLANA: u8 = 5;


// === HELPER FUNCTIONS === //
    #[view]
    public fun return_all_chain_types(): vector<String>{
        return vector<String>[convert_chainType_to_string(CHAIN_SUPRA),convert_chainType_to_string(CHAIN_SUI),convert_chainType_to_string(CHAIN_BASE),convert_chainType_to_string(CHAIN_INJECTIVE),convert_chainType_to_string(CHAIN_SOLANA)]
    }

    public fun convert_chainType_to_string(id: u8): String{
        if(id == CHAIN_SUPRA ){
            return utf8(b"Supra")
        } else if(id == CHAIN_SUI ){
            return utf8(b"Supra")
        } else if(id == CHAIN_BASE ){
            return utf8(b"Base")
        } else if(id == CHAIN_INJECTIVE ){
            return utf8(b"Injective")
        } else if(id == CHAIN_SOLANA ){
            return utf8(b"Solana")
        } else{
            return utf8(b"Unknown")
        }
    }
    public fun convert_string_to_chainType(chain: String): u8{
        if(utf8(b"Supra") == chain ){
            return CHAIN_SUPRA
        } else if(utf8(b"Sui") == chain ){
            return CHAIN_SUI
        } else if(utf8(b"Base") == chain ){
            return CHAIN_BASE
        } else if(utf8(b"Injective") == chain ){
            return CHAIN_INJECTIVE
        } else if(utf8(b"Solana") == chain ){
            return CHAIN_SOLANA
        } else{
            abort 0
        }
    }
}
