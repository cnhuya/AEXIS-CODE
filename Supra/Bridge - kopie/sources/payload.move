module dev::QiaraPayloadV65{
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;
    use aptos_std::from_bcs;
    use std::hash;
    use std::bcs;

    use dev::QiaraChainTypesV2::{Self as ChainTypes};
    use dev::QiaraTokenTypesV2::{Self as TokenTypes};
    

    const ERROR_PAYLOAD_LENGTH_MISMATCH_WITH_TYPES: u64 = 0;
    const ERROR_PAYLOAD_MISS_CHAIN: u64 = 1;
    const ERROR_PAYLOAD_MISS_TYPE: u64 = 2;
    const ERROR_PAYLOAD_MISS_HASH: u64 = 3;
    const ERROR_PAYLOAD_MISS_TIME: u64 = 4;
    const ERROR_TYPE_NOT_FOUND: u64 = 5;
    const ERROR_PAYLOAD_MISS_CONSENSUS_TYPE: u64 = 6;

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
        assert!(vector::contains(&type_names, &utf8(b"consensus_type")), ERROR_PAYLOAD_MISS_CONSENSUS_TYPE);

        let (_, chain) = find_payload_value(utf8(b"chain"), type_names, payload);
        ChainTypes::ensure_valid_chain_name(from_bcs::to_string(chain));
    //    tttta(100);
        if(vector::contains(&type_names, &utf8(b"token"))){
            let (_, token) = find_payload_value(utf8(b"token"), type_names, payload);
            TokenTypes::ensure_valid_token_nick_name(from_bcs::to_string(token));
        }

    }


/*    public fun create_identifier(addr: vector<u8>, nonce: vector<u8>, consensus_type: vector<u8>): vector<u8> {
        let vect = vector::empty<u8>();
        vector::append(&mut vect, addr);
        vector::append(&mut vect, consensus_type);
        vector::append(&mut vect, nonce);
        bcs::to_bytes(&hash::sha3_256(vect))
    }*/

    public fun create_identifier(type_names: vector<String>, payload: vector<vector<u8>>): vector<u8> {
        let (_, addr) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, consensus_type) = find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let (_, nonce) = find_payload_value(utf8(b"nonce"), type_names, payload);

        let vect = vector::empty<u8>();
        vector::append(&mut vect, addr);
        vector::append(&mut vect, consensus_type);
        vector::append(&mut vect, nonce);
        bcs::to_bytes(&hash::sha3_256(vect))
    }


    public fun find_payload_value(value: String, vect: vector<String>, from: vector<vector<u8>>): (String, vector<u8>){
        let (isFound, index) = vector::index_of(&vect, &value);
        assert!(isFound, ERROR_TYPE_NOT_FOUND);
        return (value, *vector::borrow(&from, index))
    }

    public fun prepare_bridge_deposit(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, vector<u8>, String, String, String, u64, String,){
        let (_, addr) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, symbol) = find_payload_value(utf8(b"symbol"), type_names, payload);
        let (_, chain) = find_payload_value(utf8(b"chain"), type_names, payload);
        let (_, provider) = find_payload_value(utf8(b"provider"), type_names, payload);
        //tttta(0);
        let (_, amount) = find_payload_value(utf8(b"amount"), type_names, payload);
        //tttta(5);
        let (_, hash) = find_payload_value(utf8(b"hash"), type_names, payload);

        let a = addr;
        let x = addr;
        let b = from_bcs::to_string(symbol);
        let c = from_bcs::to_string(chain);
        let d = from_bcs::to_string(provider);
        //tttta(1);
        let e = from_bcs::to_u64(amount);
        //tttta(3);
        let f = from_bcs::to_string(hash);
         //       tttta(2);
        return (a,x,b ,c ,d, e, f)
    }

    public fun prepare_register_validator(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String, String, vector<u8>){
        let (_, validator) = find_payload_value(utf8(b"validator"), type_names, payload);
        let (_, pub_key_x) = find_payload_value(utf8(b"pub_key_x"), type_names, payload);
        let (_, pub_key_y) = find_payload_value(utf8(b"pub_key_y"), type_names, payload);
        let (_, pub_key) = find_payload_value(utf8(b"pub_key"), type_names, payload);

        return (from_bcs::to_bytes(validator), from_bcs::to_string(pub_key_x), from_bcs::to_string(pub_key_y), from_bcs::to_bytes(pub_key))
    }
    public fun prepare_finalize_bridge(type_names: vector<String>, payload: vector<vector<u8>>): (vector<u8>, String,String,String,String,String, String, u64,u256, u256){
        //tttta(99);
        let (_, addr) = find_payload_value(utf8(b"addr"), type_names, payload);
        let (_, validator_root) = find_payload_value(utf8(b"validator_root"), type_names, payload);
        let (_, old_root) = find_payload_value(utf8(b"old_root"), type_names, payload);
        let (_, new_root) = find_payload_value(utf8(b"new_root"), type_names, payload);
        let (_, symbol) = find_payload_value(utf8(b"symbol"), type_names, payload);
        let (_, chain) = find_payload_value(utf8(b"chain"), type_names, payload);
        let (_, provider) = find_payload_value(utf8(b"provider"), type_names, payload);
        let (_, total_outflow) = find_payload_value(utf8(b"total_outflow"), type_names, payload);
        let (_, amount) = find_payload_value(utf8(b"amount"), type_names, payload);
        let (_, nonce) = find_payload_value(utf8(b"nonce"), type_names, payload);
       //tttta(1);
       let y = addr;
       let x = from_bcs::to_string(validator_root);
       let a = from_bcs::to_string(old_root);
      // tttta(4);
       let b = from_bcs::to_string(new_root);
       let c = from_bcs::to_string(symbol);
    //   tttta(4);
       let d = from_bcs::to_string(chain);
       let h = from_bcs::to_string(provider);
            // tttta(0);
       let e = from_bcs::to_u64(amount);
       let n = from_bcs::to_u256(total_outflow);
       //tttta(5);
       let f = from_bcs::to_u256(nonce);
         //           tttta(2);
        return (y, x, a,b,c,d,h, e, n, f)
    }

}