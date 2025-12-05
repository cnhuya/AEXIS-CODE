module dev::QiaraBridgeV1 {
    use std::signer;
    use supra_framework::account::{Self as address};
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info;
    use std::table:: {Self as table, Table};
    use std::timestamp;
    use std::bcs;
    use std::debug::print;
    use aptos_std::from_bcs;
    use aptos_std::ed25519::{Self as Crypto, Signature, UnvalidatedPublicKey};
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use supra_framework::object::{Self, Object};
    use supra_framework::primary_fungible_store;

    use dev::QiaraStorageV34::{Self as storage};

    use dev::QiaraTokensCoreV33::{Self as TokensCore};
    use dev::QiaraStakingV6::{Self as Staking};

    /// Admin address constant
    const STORAGE: address = @dev;
    const SPLITTER: u8 = 0x7C; // Pipe character '|' in UTF-8
    const SPLITTER_STR: vector<u8> = b"|";
// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_VALIDATOR_IS_ALREADY_ALLOWED: u64 = 3;
    const ERROR_INVALID_CHAIN_TYPE_ARGUMENT: u64 = 4;
    const ERROR_CHAIN_ALREADY_REGISTERED: u64 = 5;
    const ERROR_NOT_VALIDATOR: u64 = 6;
    const ERROR_DUPLICATE_EVENT: u64 = 7;
    const ERROR_INVALID_BATCH_REGISTER_EVENT_ARG_EQUALS: u64 = 8;
    const ERROR_INVALID_SIGNATURE: u64 = 9;
    const ERROR_INVALID_MESSAGE: u64 = 10;
    const ERROR_NOT_FOUND: u64 = 11;
    const ERROR_CAPS_NOT_PUBLISHED: u64 = 11;


// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    // Permissions 
    struct Permissions has key {
    }

// === STRUCTS === //
   // [DEPRECATED]
   // struct DepositEvent has store, key {}
   // struct RequestUnlockEvent has store, key {}
   // struct UnlockEvent has store, key {}

    /// In the future implement a more complext structure for storage,
    /// Making it generic for epoch (1 day for example) and adding epoch key to events, to make it
    /// so that event from epoch (ex. 14797) cant be stored/registered/validated in epoch (ex. 14798)
    /// This way we can avoid double spending attacks on other chains and also reduce storage space 
    /// which would mean more efficiency and lower gas fees by around 30-40%.

   /// counting how many times the message was "validated"
   /// If lets say it was "validated" total of 5 times succesfully, the 6th times will mote if from here
   /// to chain storage
   /// 
   /// <message> <vector<Aux>>
   /// <message> <validators, weight>
   /// <message> <validator adress, validator weight, <weight>>
   
    struct PubKeys has key {
        registry: Table<address, vector<u8>>,
    }

    struct Pending has key {
        txs: Table<vector<u8>, Votes>,
    }

    struct Validated has key {
        txs: Table<vector<u8>, Votes>,
    }

    struct Vote has key, copy, store, drop {
        validator: address,
        tx_index: u64, // i.e the last tx validator got rewardedy
        weight: u64,
    }

    struct Votes has key, copy, store, drop {
        votes: vector<Vote>,
        weight: u128,
    }

// === EVENTS === //
    #[event]
    struct ValidationEvent has copy, drop, store {
        chain_type: String,
        event_type: String,
        validator: vector<u8>,
        message: vector<u8>,
    }

    #[event]
    struct EventRegistered has copy, drop, store {
        chain_type: String,
        event_type: String,
        validator: vector<u8>,
        validators: vector<ValidatorVote>,
        recipient: address,
        message: vector<u8>,
        token_type: String,
        amount: u64,
        time: u64
    }
// === INIT === //
    fun init_module(admin: &signer) {
    //    if (!exists<Permissions>(@dev)) {
    //        let _cap = Permissions { vault_access: Vaults::give_access(admin), coin_access: CoinDeployer::give_access(admin)};
    //        move_to(admin, _cap);
    //    };
    }

// === FUNCTIONS === //
   
    public entry fun register_event(validator: &signer, validator_pubkey: vector<u8>, _signature: vector<u8>, message: vector<u8>) acquires Pending, Validated, PubKeys, Permissions {

        ensure_validator_pubkey(borrow_global_mut<PubKeys>(@dev), validator, validator_pubkey);

        print(&utf8(b" SENDER "));
        print(&signer::address_of(validator));
        print(&utf8(b" abc "));

        let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(validator_pubkey);
        let signature = Crypto::new_signature_from_bytes(_signature);
        let verified = Crypto::signature_verify_strict(&signature, &pubkey_struct, message);
        assert!(verified, ERROR_INVALID_SIGNATURE);

        let pending = borrow_global_mut<Pending>(STORAGE);
        let validated = borrow_global_mut<Validated>(STORAGE);

        // Store event in both pending and chain storage
        handle_event(
            validator,
            (signer::address_of(validator)),
            &mut pending.txs,
            &mut validated.txs,
            message,
        );
    }

    fun ensure_validator_pubkey(pubkeys_registry: &mut PubKeys, validator: &signer, validator_pubkey: vector<u8>) {
        print(&vector::length(&validator_pubkey));

        if(!table::contains(&pubkeys_registry.registry, signer::address_of(validator))) {
            table::add(&mut pubkeys_registry.registry, signer::address_of(validator), validator_pubkey);
        };
    }


    fun handle_event(signer: &signer, validator: address, pending_table: &mut table::Table<vector<u8>, Aux>, validated_table: &mut table::Table<vector<u8>, Aux>, message: vector<u8>) acquires Permissions {
        let quorum = storage::expect_u128(storage::viewConstant(utf8(b"QiaraChains"), utf8(b"QUARUM")));

        // Already validated?
        if (table::contains(validated_table, message)) {
            abort(ERROR_DUPLICATE_EVENT);
        };

        let vote_weight = Staking::get_voting_power(address);
        // Update pending validators
        let count = if (table::contains(pending_table, message)) {
            let _quar = table::borrow_mut(pending_table, message);
            if(vector::contains(&_quar.validators, validator)){
                let vote = ValidatorVote { validator: validator, weight: vote_weight };
                _quar.weight = _quar.weight + (vote_weight as u128);
                vector::push_back(&mut _quar.validators, vote);
            };
            _quar.weight
        } else {
            let validator_vote = ValidatorVote {validator: validator, weight: vote_weight};
            let vect = vector<ValidatorVote>[validator_vote];
            let quar = Aux {validators: vect, weight: (vote_weight as u128)};
            table::add(pending_table, copy message, quar);

        //    let event_id = from_bcs::to_u8(copy_range(&message, 0, 1));
        //    event::emit(ValidationEvent {
        //        chain_type: ChainTypes::convert_chainType_to_string<T>(),
        //        event_type: convert_eventID_to_string(event_id),
        //        validator: validator,
        //        message: message,
        //    });
            1
        };


        // Promote to validated
        if (count >= (quorum as u128)) {
            // Defensive: ensure key exists before remove
            assert!(table::contains(pending_table, message), ERROR_NOT_FOUND);
            let validators = table::remove(pending_table, message);

            if (table::contains(validated_table, message)) {
                abort(ERROR_DUPLICATE_EVENT);
            };
            table::add(validated_table, message, validators);

            // Decode fields (we already length-checked)
       //     let event_id = from_bcs::to_u8(copy_range(&message, 0, 1));
       //     let user_addr = from_bcs::to_address(copy_range(&message, 1, 33));
       //     let lend_rate =  from_bcs::to_u64(copy_range(&message, 33, 41)); // u64 is 8 bytes
       //     let borrow_rate =  from_bcs::to_u64(copy_range(&message, 41,49)); // u64 is 8 bytes
       //     let amount = from_bcs::to_u64(copy_range(&message, 49, 57)); 
            //let vault_provider = copy_range(&message, 89, len); // 
            //let _native_tx_hash = copy_range(&message, 41, 73); // keep if youll use it later

            // >>> PROBABLE CRASH SITE BEFORE: make sure Caps exists <<<
            assert!(exists<Permissions>(@dev), ERROR_CAPS_NOT_PUBLISHED);
            let cap = borrow_global<Permissions>(@dev);

            // If these are needed later, keep; otherwise remove to avoid unused warnings.
            let _coin_cap = CoinDeployer::give_usercap(signer, &cap.coin_access);
            let _user_cap = Vaults::give_usercap(signer, &cap.vault_access);

            let even_type = 1;
            if(even_type == utf8(b"Deposit")){
              //  let coins = CoinDeployer::extract_to<E>(signer, _coin_cap, user_addr, amount);
            //    Vaults::bridge_deposit<E,T,X>(signer, &cap.vault_access, _user_cap, user_addr, amount, coins, lend_rate, borrow_rate);
            } else if(even_type == utf8(b"Request Unlock")){
            //   Vaults::request_unlock<E>(signer, user_addr, amount, &_user_cap);
            } else if(even_type == utf8(b"Unlock")){
            //   Vaults::unlock<E>(signer, user_addr, amount, &_user_cap);
            }  else{
                abort(ERROR_INVALID_MESSAGE);
            };
        //    let _validators = copy validators;
        /*    event::emit(EventRegistered {
                chain_type: ChainTypes::convert_chainType_to_string<T>(),
                event_type: even_type,
                validator: copy validator,
                validators: validators.validators,
                recipient: user_addr,
                message: message,
                token_type: type_info::type_name<E>(),
                amount: amount,
                time: timestamp::now_seconds(),
            });*/
        };
    }



    #[view]
    public fun is_validated_single(message: vector<u8>): bool acquires Validated {
        let validated = borrow_global<Validated>(@dev);
            if (table::contains(&validated.txs, message)) {
                return true
            } else {
                return false
            }
    }


    #[view]
    public fun is_validated(messages: vector<vector<u8>>): vector<bool> acquires Validated {
        let validated = borrow_global<Validated>(@dev);

        let results = vector::empty<bool>();
        let len = vector::length(&messages);
        let i = 0;

        while (i < len) {
            let message = vector::borrow(&messages, i);
            if (table::contains(&validated.txs, *message)) {
                vector::push_back(&mut results, true);
            } else {
                vector::push_back(&mut results, false);
            };
            i = i + 1;
        };

        results
    }



    fun convert_eventID_to_string(eventID: u8): String{
        if(eventID == 1 ){
            return utf8(b"Deposit")
        } else if(eventID == 2 ){
            return utf8(b"Request Unlock")
        } else if(eventID == 3 ){
            return utf8(b"Unlock")
        } else{
            return utf8(b"Unknown")
        }
    }



    #[test(account = @0x1, owner = @0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd, owner2 = @0x281d0fce12a353b1f6e8bb6d1ae040a6deba248484cf8e9173a5b428a6fb74e7)]
    public entry fun test(account: signer, owner: signer, owner2: signer) acquires  Chain, Pending, Validated, Caps{
        // Initialize the CurrentTimeMicroseconds resource
        supra_framework::timestamp::set_time_has_started_for_testing(&account);
        supra_framework::timestamp::update_global_time_for_test(50000);
        let t1 =  supra_framework::timestamp::now_seconds();
        print(&t1);
        // Initialize the module
        init_module(&owner);
        // Change config
        let addr = signer::address_of(&owner);
        let addr2 = signer::address_of(&owner2);
        // Register a new chain
       // register_chain<Sui>(&owner, 1, utf8(b"Sui"), utf8(b"SUI"));
       // register_chain<Base>(&owner, 2, utf8(b"Base"), utf8(b"BASE"));
       // register_chain<Supra>(&owner, 3, utf8(b"Supra"), utf8(b"SUPRA"));           

        // Allow a validator


        let pubkey: vector<u8> = vector[
            0xbe, 0x4e, 0x29, 0x0a, 0x50, 0x82, 0xe6, 0xeb,
            0x0d, 0x01, 0x64, 0x1c, 0x4d, 0x35, 0x39, 0xf7,
            0x42, 0x33, 0x05, 0xac, 0xd9, 0x47, 0x42, 0xa0,
            0xe6, 0x23, 0x88, 0x2c, 0xae, 0x3d, 0x1d, 0xfd
        ];

        let pubkey2: vector<u8> = vector[
            0xd2, 0xf4, 0x24, 0x47, 0x42, 0xc8, 0x17, 0x76,
            0x50, 0x3b, 0x8e, 0x45, 0xc4, 0xba, 0x6f, 0x7e,
            0x87, 0x8d, 0x96, 0xe0, 0xd9, 0x74, 0xef, 0x51,
            0x6b, 0x99, 0x25, 0x09, 0xeb, 0x08, 0x5b, 0xcd
        ];

    let serialized_signature: vector<u8> = vector[
        0xfc, 0x3c, 0xa9, 0x97, 0x1c, 0x22, 0x62, 0x60,
        0x4c, 0xd4, 0xe0, 0xda, 0x9d, 0xa2, 0xa7, 0x87,
        0x5b, 0x3a, 0x15, 0x61, 0xd6, 0x32, 0x9b, 0x68,
        0xbf, 0xc1, 0x47, 0xb6, 0x75, 0xbc, 0xc5, 0x2d,
        0xa6, 0xe7, 0x9b, 0x40, 0x9e, 0xa9, 0x50, 0x90,
        0xfc, 0x36, 0x97, 0xd6, 0xdf, 0xcd, 0x22, 0x2f,
        0x36, 0xec, 0x71, 0x9d, 0xd7, 0xdd, 0x09, 0xf8,
        0x1f, 0x4f, 0x5e, 0xa5, 0xb1, 0x69, 0x3b, 0x02
    ];

    let serialized_payload: vector<u8> = vector[
        0x01, 0x51, 0x5b, 0xbf, 0xb8, 0x77, 0x80, 0x44,
        0xab, 0x8f, 0xa5, 0x39, 0x3f, 0x89, 0x84, 0x4e,
        0x5e, 0x27, 0x45, 0x44, 0x45, 0xc7, 0xc6, 0x5a,
        0x91, 0x5e, 0x60, 0x28, 0xdf, 0x40, 0x2d, 0x50,
        0x82, 0x65, 0xad, 0x96, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xcd, 0xde, 0x99, 0x47, 0x1a, 0x73,
        0x41, 0xc7, 0x3d, 0x3c, 0x78, 0xa2, 0x12, 0x8f,
        0x16, 0xff, 0x82, 0x74, 0x12, 0x52, 0xbb, 0xb7,
        0x89, 0xe9, 0x36, 0x8d, 0x98, 0x37, 0x9e, 0x2b,
        0x8c, 0xdd
    ];


        allow_validator<Base>(&owner, addr, pubkey);
        allow_validator<Supra>(&owner, addr, pubkey);
        allow_validator<Sui>(&owner, addr, pubkey);

        allow_validator<Base>(&owner, addr2, pubkey2);
        allow_validator<Supra>(&owner, addr2, pubkey2);
        allow_validator<Sui>(&owner, addr2, pubkey2);


        let validators = get_chain_validators<Sui>();  

        print(&utf8(b" VALIDATORS "));
        print(&validators);
       // print(&vector::length(&serialized_signature));

      //  struct eth has drop, store {}

        register_event<Sui,Sui>(&owner, serialized_signature , serialized_payload); 

        register_event<Sui,Sui>(&owner2, serialized_signature , serialized_payload);           
 //       print(&deserialize_message(&serialized_payload));

    }
}

