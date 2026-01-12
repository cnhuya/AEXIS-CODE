module dev::Qiarax8 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::ed25519;
    use aptos_std::table::{Self, Table};
    //use aptos_std::any::{Self, Any};
    use supra_framework::event;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{Self as String, String, utf8};
    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_INVALID_SIGNATURE: u64 = 1001;
    const ERROR_QUORUM_NOT_MET: u64 = 1002;
    const ERROR_STATE_NOT_FOUND: u64 = 1003;

    // === STRUCTS === //

    struct ValidatorBody has key, store, copy, drop {
        pub_key: vector<u8>,
        index: u64, // Position in the 64-validator array (0-63)
    }
    struct ValidatorStake has key, store, copy, drop {
        pub_key: vector<u8>,
        stake: u64,
    }

    struct Any has store, copy, drop{
        value: vector<u8>,
        type: String,
        id: u64
    }

    struct Variables has key {
        map: Map<u64, Any>,
    }

    struct Validators has key {
        table: Table<address, ValidatorStake>,
    }
    // This resource stores the "Agreed" state before it moves to Ethereum
    struct BridgeState has key, drop, copy, store {
        epoch: u64,
        votes: u64, //Vote Count
        // I need to make it like this, bcs sometimes the validators can be different for different values is it possible? i.e sometimes validators can be offline so other validators validate instead of them
        validators: Map<address, ValidatorBody>,
    }

    struct States has key {
        table: Table<vector<u8>, BridgeState>,
    }

    #[event]
    struct BridgeUpdateEvent has drop, store {
        epoch: u64,
        return_variables: Map<u64, Any>,
        variable_id: u64,
        new_value: vector<u8>,
        poseidon_root: vector<u8>,
    }
    #[event]
    struct VoteEvent has drop, store {
        validator: address,
        time: u64,
        message: vector<u8>,
        signature: vector<u8>,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, Variables {map: map::new<u64, Any>()});
        move_to(admin, Validators {table: table::new<address, ValidatorStake>()});
        move_to(admin,  States {table: table::new<vector<u8>, BridgeState>()});
    }

    // === LOGIC === //
    public entry fun test_save_validator(signer: &signer, validator: address, pub_key: vector<u8>, stake: u64) acquires Validators {
        // 1. Use borrow_global_mut to allow modifications
        let config = borrow_global_mut<Validators>(@dev); 
        
        let body = ValidatorStake { pub_key: pub_key, stake: stake };
        
        // 2. Now &mut config.table is valid
        table::upsert(&mut config.table, validator, body);    
    }

    // === LOGIC === //
    public entry fun test_save_variable(signer: &signer, variable_id: u64, type: String, value: vector<u8>) acquires Variables {
        // 1. Use borrow_global_mut to allow modifications
        let config = borrow_global_mut<Variables>(@dev); 
        
        let any = Any { value:value, type:type, id: variable_id };
        
        // 2. Now &mut config.table is valid
        map::upsert(&mut config.map, variable_id, any);  
    }


    /// Validators call this to "vote" on a new Shadow Root calculated by the relayer
    public entry fun validate_and_vote(validator: &signer,poseidon_root: vector<u8>,variable_id: u64,new_value: vector<u8>, value_type: String, signature: vector<u8>) acquires Variables, Validators, States {
        let addr = signer::address_of(validator);
        let validators = borrow_global<Validators>(@dev);
        
        // 1. Check if sender is a valid validator
        assert!(table::contains(&validators.table, addr), ERROR_NOT_VALIDATOR);
        let val_info = table::borrow(&validators.table, addr);

        // 2. Cryptographic Verification of the Vote
        // The message is the combination of (root + id + value + epoch)
        let message = poseidon_root; // Simplify: in reality, concat all fields
        let pk = ed25519::new_unvalidated_public_key_from_bytes(val_info.pub_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        assert!(ed25519::signature_verify_strict(&sig, &pk, message), ERROR_INVALID_SIGNATURE);

        // 3. Updating State (i.e innitializing the state if it doesn't exist)
        let state_table = borrow_global_mut<States>(@dev);
        if (!table::contains(&state_table.table, poseidon_root)) {

            let bridge_state = BridgeState {
                epoch: 0,
                votes: 0,
                validators: map::new<address, ValidatorBody>(), 
            };
                table::add(&mut state_table.table, poseidon_root, bridge_state);
        };
        let state = table::borrow_mut(&mut state_table.table, poseidon_root);
        // 4. Vote mechanism
        state.votes = state.votes + 1;

        if (!map::contains_key(&state.validators, &addr)) {
            let validator_index = map::length(&state.validators);
            map::add(&mut state.validators, addr, ValidatorBody {pub_key: val_info.pub_key, index:validator_index});
        };

        event::emit(VoteEvent {
            validator: addr,
            time: timestamp::now_seconds(),
            message:message,
            signature: signature
        });

        // 5. Threshold Check (e.g., 19/28 or > 2/3 of 64)
        if (state.votes >= 2) {
            state.epoch = state.epoch + 1;
            let variables = borrow_global_mut<Variables>(@dev);
            map::upsert(&mut variables.map, variable_id, Any { value: new_value, type: value_type, id: variable_id });
            // Emit the event that the Relayer uses to build the ZK Proof
            event::emit(BridgeUpdateEvent {
                epoch: state.epoch,
                return_variables: return_variables(),
                variable_id,
                new_value: bcs::to_bytes(&new_value),
                poseidon_root,
            });
        }
    }


    #[view]
    public fun return_variables(): Map<u64, Any> acquires Variables {
        let vars = borrow_global<Variables>(@dev);

        vars.map // Note the ampersand for reference
    }

    #[view]
    public fun return_state(poseidon_root: vector<u8>): BridgeState acquires States {
        let state = borrow_global<States>(@dev);
        if(!table::contains(&state.table, poseidon_root)) {
            abort ERROR_STATE_NOT_FOUND
        } else {
            *table::borrow(&state.table, poseidon_root)
        }
    }

}