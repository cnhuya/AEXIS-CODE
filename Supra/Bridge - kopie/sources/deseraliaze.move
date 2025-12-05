module dev::QiaraDeserealizeV1 {
    use std::signer;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table;

    use dev::QiaraChainTypesV19::{Self as ChainTypes};
    
    const valid_idvalid_message_typess: vector<u8> = vector[0,1,2,3,4,5,6];

    const ERROR_INVALID_MESSAGE_TYPE: u64 = 0;
    const ERROR_SPLIT_LENGHT_TOO_SHORT: u64 = 1;
    const ERROR_INVALID_TIME_FORMAT: u64 = 2;
    const ERROR_INVALID_HASH_FORMAT: u64 = 3;

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == ADMIN, 1);
    }

    #[view]
    public fun raw_deserialize_message(message: vector<u8>): (vector<vector<u8>>, u64) {
        ensure_security(message);
        let parts = split(&message, SPLITTER);
        (parts, vector::length(&parts))
    }



// time, hash, message_type(u8), chain_type(u8),

// returns
    public fun return_message_time(message: vector<u8>): u64{
        ensure_security(message);
        let parts = split(&message, SPLITTER);
        from_bcs::to_u64(&vector::borrow(&parts, 0));
    }
    public fun return_message_chain(message: vector<u8>): String{
        ensure_security(message);
        let parts = split(&message, SPLITTER);
        from_bcs::to_string(&vector::borrow(&parts, 1));
    }
    public fun return_message_type(message: vector<u8>): u8{
        ensure_security(message);
        let parts = split(&message, SPLITTER);
        from_bcs::to_u8(&vector::borrow(&parts, 2));
    }
    public fun return_message_chain(message: vector<u8>): u8{
        ensure_security(message);
        let parts = split(&message, SPLITTER);
        from_bcs::to_u8(&vector::borrow(&parts, 3));
    }

    fun ensure_security(message: vector<u8>){
        let parts = split(&message, SPLITTER);
        assert!(vector::length(&parts) > 4, ERROR_SPLIT_LENGHT_TOO_SHORT);

        let time = vector::borrow(&parts, 0);
        assert!(vector::length(&time) = 10, ERROR_INVALID_TIME_FORMAT);

        let hash = from_bcs::to_string(&vector::borrow(&parts, 1));
        assert!(string::length(&hash) = 64, ERROR_INVALID_HASH_FORMAT);

        let message_type = from_bcs::to_u8(&vector::borrow(&parts, 2));
        assert!(vector::contains(valid_message_types, &message_type), ERROR_INVALID_MESSAGE_TYPE);

        let chain_type = from_bcs::to_u8(&vector::borrow(&parts, 3));
        ChainTypes::ensure_valid_chain_id(chainID);
    }

    fun split(v: &vector<u8>, delimiter: u8): vector<vector<u8>> {
        let parts = vector::empty<vector<u8>>();
        let current_part = vector::empty<u8>();
        let i = 0;
        let len = vector::length(v);
        
        while (i < len) {
            let byte = *vector::borrow(v, i);
            if (byte == delimiter) {
                // Save current part and start new one
                vector::push_back(&mut parts, current_part);
                current_part = vector::empty<u8>();
            } else {
                vector::push_back(&mut current_part, byte);
            };
            i = i + 1;
        };
        
        // Don't forget the last part
        vector::push_back(&mut parts, current_part);
        parts
    }

    fun copy_range(v: &vector<u8>, start: u64, end: u64): vector<u8> {
        let out = vector::empty<u8>();
        let i = start;
        while (i < end) {
            let b_ref = vector::borrow(v, i);
            vector::push_back(&mut out, *b_ref);
            i = i + 1;
        };
        out
    }
}