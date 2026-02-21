module dev::QiaraEventV53 {
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


    public fun create_identifier(addr: vector<u8>, nonce: vector<u8>, consensus_type: vector<u8>): vector<u8> {
        let vect = vector::empty<u8>();
        vector::append(&mut vect, addr);
        vector::append(&mut vect, consensus_type);
        vector::append(&mut vect, nonce);
        bcs::to_bytes(&hash::sha3_256(vect))
    }

// Pubic
    public fun create_data_struct(name: String, type: String, value: vector<u8>): Data {
        Data {name: name,type: type,value: value}
    }

    public fun emit_market_event(type: String, data: vector<Data>) { 
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
        event::emit(MarketEvent {
            name: type,
            aux: data,
        });

    }
    public fun emit_points_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(PointsEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_governance_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});  
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier)); 
         event::emit(GovernanceEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_perps_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
       // let identifier = create_identifier(data);
        //vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(PerpsEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_staking_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
      //  let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(StakingEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_bridge_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(BridgeEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_consensus_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
      //  let identifier = create_identifier(data);
        //vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(ConsensusEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_crosschain_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(CrosschainEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_validation_event(type: String, data: vector<Data>) {
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


}
