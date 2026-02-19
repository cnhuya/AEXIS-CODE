module dev::QiaraEventV27 {
    use std::vector;
    use std::signer;
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::hash;
    use supra_framework::event;

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_TOKEN_PRICE_COULDNT_BE_FOUND: u64 = 1;
    const ERROR_INVALID_CONSENSUS_TYPE: u64 = 2;
    
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

// === STRUCTS === //
    struct Data has key, copy, drop, store{
        name: String,
        type: String,
        value: vector<u8>,
    }

// === EVENTS === //
    #[event]
    struct MarketEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct PerpsEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct GovernanceEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct PointsEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct StakingEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct BridgeEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ConsensusEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct CrosschainEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ValidationEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ConsensusVoteEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct LeavesChange has copy, drop, store {
        type: String,
        aux: vector<u256>,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);
    }

    public fun create_identifier(data: vector<Data>): vector<u8> {
        let addr = extract_value(&data, utf8(b"addr"));
    //    let consensus_type = extract_value(&data, utf8(b"consensus_type"));
        let nonce = extract_value(&data, utf8(b"nonce"));

        let vect = vector::empty<u8>();
        vector::append(&mut vect, addr);
      //  vector::append(&mut vect, consensus_type);
        vector::append(&mut vect, nonce);
        bcs::to_bytes(&hash::sha3_256(vect))
    }


    fun extract_value(data: &vector<Data>, name: String): vector<u8> {
        let i = 0;
        let len = vector::length(data);
        while (i < len) {
            let d = vector::borrow(data, i);
            if (&d.name == &name) {
                return d.value
            };
            i = i + 1;
        };
        abort 404 // Or return an empty vector
    }

// Pubic
    public fun create_data_struct(name: String, type: String, value: vector<u8>): Data {
        Data {name: name,type: type,value: value}
    }

    public fun emit_market_event(type: String, data: vector<Data>, consensus_type: String) { 
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
        event::emit(MarketEvent {
            name: type,
            aux: data,
        });

    }
    public fun emit_points_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(PointsEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_governance_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});  
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier)); 
         event::emit(GovernanceEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_perps_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(PerpsEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_staking_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(StakingEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_bridge_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(BridgeEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_consensus_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(ConsensusEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_crosschain_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
        let identifier = create_identifier(data);
        vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(CrosschainEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_validation_event(type: String, data: vector<Data>, consensus_type: String) {
        append_consensus_type(&mut data, consensus_type);
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ValidationEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_consensus_vote_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ConsensusVoteEvent {
            aux: data,
        });
    }
    public fun emit_consensus_register_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ConsensusVoteEvent {
            aux: data,
        });
    }
    public fun emit_leaves_event(type: String, data: vector<u256>) {
         event::emit(LeavesChange {
            type: type,
            aux: data,
        });
    }

// Internal
// THIS IS RIGHT: It modifies the actual vector in place
    fun append_consensus_type(data: &mut vector<Data>, consensus_type: String) {
        assert!(
            consensus_type == utf8(b"zk") || 
            consensus_type == utf8(b"native") || 
            consensus_type == utf8(b"none") || 
            consensus_type == utf8(b"proof"), 
            ERROR_INVALID_CONSENSUS_TYPE
        );
        let type_struct = create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type));
        vector::push_back(data, type_struct);
    }

}
