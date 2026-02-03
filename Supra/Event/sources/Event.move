module dev::QiaraEventV3 {
    use std::vector;
    use std::signer;
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use supra_framework::event;

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_TOKEN_PRICE_COULDNT_BE_FOUND: u64 = 1;
    
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
        aux: vector<Data>,
    }
    #[event]
    struct PerpsEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct GovernanceEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct PointsEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct StakingEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct BridgeEvent has copy, drop, store {
        aux: vector<Data>,
    }


// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);
    }

    public fun create_data_struct(name: String, type: String, value: vector<u8>): Data {
        Data {name: name,type: type,value: value}
    }

    public fun emit_market_event(type: String, data: vector<Data>) { 
         data = append_type(data, type); 
         vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
         event::emit(MarketEvent {
            aux: data,
        });

    }
    public fun emit_points_event(type: String, data: vector<Data>) {
         data = append_type(data, type);
         vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
         event::emit(PointsEvent {
            aux: data,
        });
    }
    public fun emit_governance_event(type: String, data: vector<Data>) {
         data = append_type(data, type);
         vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
         event::emit(GovernanceEvent {
            aux: data,
        });
    }
    public fun emit_perps_event(type: String, data: vector<Data>) {
         data = append_type(data, type);
         vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
         event::emit(PerpsEvent {
            aux: data,
        });
    }
    public fun emit_staking_event(type: String, data: vector<Data>) {
         data = append_type(data, type);
         vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
         event::emit(StakingEvent {
            aux: data,
        });
    }
    public fun emit_bridge_event(type: String, data: vector<Data>) {
         data = append_type(data, type);
         vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
         event::emit(BridgeEvent {
            aux: data,
        });
    }

    fun append_type(data: vector<Data>, type: String): vector<Data> {
        let type = create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&type));
        let vect = vector[type];
        vector::append(&mut vect, data);
        return vect
    }

}
