module dev::QiaraPayloadV33 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use aptos_std::from_bcs;

    use dev::QiaraChainTypesV4::{Self as ChainTypes};
    use dev::QiaraTokenTypesV4::{Self as TokenTypes};
    

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

    fun tttta(error: u64){
        abort error
    }

    public fun ensure_valid_payload(type_names: vector<String>, payload: vector<vector<u8>>){
        let len = vector::length(&type_names);
        let payload_len = vector::length(&payload);
        assert!(len == payload_len, ERROR_PAYLOAD_LENGTH_MISMATCH_WITH_TYPES);

       // assert!(vector::contains(&type_names, &utf8(b"hash")), ERROR_PAYLOAD_MISS_HASH);
        assert!(vector::contains(&type_names, &utf8(b"time")), ERROR_PAYLOAD_MISS_TIME);
        assert!(vector::contains(&type_names, &utf8(b"type")), ERROR_PAYLOAD_MISS_TYPE);

        let (_, chain) = find_payload_value(utf8(b"chain"), type_names, payload);
        ChainTypes::ensure_valid_chain_name(from_bcs::to_string(chain));
    //    tttta(100);
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
    public fun prepare_register_validator(type_names: vector<String>, payload: vector<vector<u8>>): (String, String, String, vector<u8>){
        let (_, shared_storage_name) = find_payload_value(utf8(b"shared_storage_name"), type_names, payload);
        let (_, pub_key_x) = find_payload_value(utf8(b"pub_key_x"), type_names, payload);
        let (_, pub_key_y) = find_payload_value(utf8(b"pub_key_y"), type_names, payload);
        let (_, pub_key) = find_payload_value(utf8(b"pub_key"), type_names, payload);

        return (from_bcs::to_string(shared_storage_name), from_bcs::to_string(pub_key_x), from_bcs::to_string(pub_key_y), from_bcs::to_bytes(pub_key))
    }
    public fun prepare_finalize_bridge(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String,String,String,String, String, u64){
        //tttta(99);
        let (_, receiver) = find_payload_value(utf8(b"receiver"), type_names, payload);
        let (_, validator_root) = find_payload_value(utf8(b"validator_root"), type_names, payload);
        let (_, old_root) = find_payload_value(utf8(b"old_root"), type_names, payload);
        let (_, new_root) = find_payload_value(utf8(b"new_root"), type_names, payload);
        let (_, symbol) = find_payload_value(utf8(b"symbol"), type_names, payload);
        let (_, chain) = find_payload_value(utf8(b"chain"), type_names, payload);
        let (_, amount) = find_payload_value(utf8(b"amount"), type_names, payload);
       //tttta(1);
       let y = from_bcs::to_bytes(receiver);
       let x = from_bcs::to_string(validator_root);
       let a = from_bcs::to_string(old_root);
    //   tttta(4);
       let b = from_bcs::to_string(new_root);
       let c = from_bcs::to_string(symbol);
    //   tttta(4);
       let d = from_bcs::to_string(chain);
            // tttta(0);
       let e = from_bcs::to_u64(amount);
               //     tttta(2);
        return (y, x, a,b,c,d,e)
    }

}