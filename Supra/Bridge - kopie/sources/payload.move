module dev::QiaraPayloadV8 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use aptos_std::from_bcs;

    use dev::QiaraChainTypesV5::{Self as ChainTypes};
    use dev::QiaraTokenTypesV5::{Self as TokenTypes};
    

    const ERROR_PAYLOAD_LENGTH_MISMATCH_WITH_TYPES: u64 = 0;
    const ERROR_PAYLOAD_MISS_CHAIN: u64 = 1;
    const ERROR_PAYLOAD_MISS_TYPE: u64 = 2;
    const ERROR_PAYLOAD_MISS_HASH: u64 = 3;
    const ERROR_PAYLOAD_MISS_TIME: u64 = 4;
    const ERROR_TYPE_NOT_FOUND: u64 = 5;

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);
    }


    public fun unpack_payload(vect: vector<vector<u8>>): vector<u8>{
        let len = vector::length(&vect);
        let out = vector::empty<u8>();
        while(len>0){
            let el = vector::borrow(&vect, len-1);
            len = len - 1;
            vector::append(&mut out, *el);
        };
        return out
    }

    public fun ensure_valid_payload(type_names: vector<String>, payload: vector<vector<u8>>){
        let len = vector::length(&type_names);
        let payload_len = vector::length(&payload);
        assert!(len == payload_len, ERROR_PAYLOAD_LENGTH_MISMATCH_WITH_TYPES);

        assert!(vector::contains(&type_names, &utf8(b"chain")), ERROR_PAYLOAD_MISS_CHAIN);
        assert!(vector::contains(&type_names, &utf8(b"hash")), ERROR_PAYLOAD_MISS_HASH);
        assert!(vector::contains(&type_names, &utf8(b"time")), ERROR_PAYLOAD_MISS_TIME);
        assert!(vector::contains(&type_names, &utf8(b"type")), ERROR_PAYLOAD_MISS_TYPE);

        let (_, chain) = find_payload_value(utf8(b"chain"), type_names, payload);
        ChainTypes::ensure_valid_chain_name(from_bcs::to_string(chain));

        if(vector::contains(&type_names, &utf8(b"token"))){
            let (_, token) = find_payload_value(utf8(b"token"), type_names, payload);
            TokenTypes::ensure_valid_token_nick_name(from_bcs::to_string(token));
        }

    }

    public fun find_payload_value(value: String, vect: vector<String>, from: vector<vector<u8>>): (String, vector<u8>){
        let (isFound, index) = vector::index_of(&vect, &value);
        assert!(isFound, ERROR_TYPE_NOT_FOUND);
        return (value, *vector::borrow(&from, index))
    }

}