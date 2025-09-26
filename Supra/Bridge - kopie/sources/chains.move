module dev::AexisChainsV50 {
    use std::signer;
    use supra_framework::account::{Self as address};
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::type_info;
    use std::table;
    use std::timestamp;
    use std::bcs;
    use std::debug::print;
    use aptos_std::from_bcs;
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use supra_framework::object::{Self, Object};
    use supra_framework::primary_fungible_store;

    use dev::QiaraStorageV20::{Self as storage};
    
    use dev::AexisCoinTypesV2::{Self as CoinDeployer, AccessCoins, UserCoinsCap};

    use dev::AexisVaultsV18::{Self as Vaults, UserCap, Access};

    use aptos_std::ed25519::{Self as Crypto, Signature, UnvalidatedPublicKey};

    /// Admin address constant
    const STORAGE: address = @dev; // <-- replace with real admin address
    const QIARA_TOKEN: address = @0xf6d11e5ace09708c285e9dbabb267f4c4201718aaf0e0a70664ae48aaa38452f;


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


   // struct testETH has drop, store {}

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
   /// <message> <vector<QUAR>>
   /// <message> <validators, weight>
   /// <message> <validator adress, validator weight, <weight>>
   
    struct Pending<phantom T> has key {
        txs: table::Table<vector<u8>, Quar>,
    }

    struct Validated<phantom T> has key {
        txs: table::Table<vector<u8>, Quar>,
    }

    struct ValidatorVote has key, copy, store, drop {
        validator: vector<u8>,
        weight: u64,
    }

    struct Quar has key, copy, store, drop {
        validators: vector<ValidatorVote>,
        weight: u128,
    }

    // Permissions 
    struct Caps has key {
        vault_access: Access,
        coin_access: AccessCoins,
    }

    // Validator should be a key type so it can be stored in Chain
    struct Validator has store, copy, drop {
        address: address,
        pubkey: vector<u8>,
    }

    struct DeserializedTX has store, drop, key {
        native_tx_hash: vector<u8>,
        event_type: String,
        user: vector<u8>,
        vault_provider: String,
        vault_lend_rate: u64,
        vault_borrow_rate: u64,
        amount: u64,
    }


    #[event]
    struct ValidationEvent has copy, drop, store {
        chain_type: String,
        event_type: String,
    //    creator: vector<u8>,
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

    fun init_module(admin: &signer) {
        if (!exists<Caps>(STORAGE)) {
            let _cap = Caps { vault_access: Vaults::give_access(admin), coin_access: CoinDeployer::give_access(admin)};
            move_to(admin, _cap);
        };

        assert!(exists<Caps>(STORAGE), ERROR_NOT_FOUND);
        //assert!(!exists<Chain<Supra>>(signer::address_of(admin)), ERROR_NOT_FOUND);

        register_chain<Sui>(admin, 1, utf8(b"Sui Network"), utf8(b"SUI"));
        register_chain<Base>(admin, 2, utf8(b"Base Chain"), utf8(b"BASE"));
        register_chain<Supra>(admin, 3, utf8(b"Supra"), utf8(b"SUPRA"));

    }


    fun get_qiara_balance(addr: address): u64 {
        fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(addr, object::address_to_object<Metadata>(QIARA_TOKEN)))
    }

    fun get_qiara_circ_supply(addr: address): u64 {
        fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(addr, object::address_to_object<Metadata>(QIARA_TOKEN)))
    }

    public entry fun register_chain<T>(admin: &signer, id: u8, name: String, symbol: String) {
        assert!(!exists<Chain<T>>(signer::address_of(admin)), ERROR_CHAIN_ALREADY_REGISTERED);

        let chain = Chain<T> { 
            id, 
            name, 
            symbol, 
            validators: vector::empty<Validator>(),
        };

        // pending storage (temporary validation counters)
        let pending_txs_table = table::new<vector<u8>, Quar>();
        let validated_txs_table = table::new<vector<u8>, Quar>();

        let pending = Pending<T> { 
            txs: pending_txs_table,
        };
        let validated = Validated<T> { 
            txs: validated_txs_table,
        };

        move_to(admin, chain);
        move_to(admin, pending);
        move_to(admin, validated);
    }


    ///
    /// TO DO
    /// 
    /// Implement manual event registration, bridge aggregrator would then check the tx hash offchain and emit new event registration,
    /// unless all asserts are passed (transaction type is allowed (package,module,function...) or check txs if allowed in certain blockchains)
    /// 

    ///[DEPRECATED]
  //  public entry fun batch_register_event<T: store, E>(admin: &signer, signatures: vector<vector<u8>>, messages: vector<vector<u8>>) acquires Chain,Pending, Validated, Caps{
        //assert!(vector::length(&native_tx_hash) == vector::length(&user) && vector::length(&user) == vector::length(&amount), ERROR_INVALID_BATCH_REGISTER_EVENT_ARG_EQUALS);
         //let len = vector::length(&messages);
   //     while(len>0){
    //        register_event<T, E>(admin, *vector::borrow(&signatures, len-1), *vector::borrow(&messages, len-1));
     //       len = len-1;
      //  };
    //}

public entry fun register_event<T: store, E, X:store>(sender: &signer, _signature: vector<u8>, message: vector<u8>) acquires Chain, Pending, Validated, Caps {
    let chain = borrow_global_mut<Chain<T>>(STORAGE);
    let vault_provider = type_info::type_name<X>();
    vector::append(&mut message, *String::bytes(&vault_provider));
    // Check validator and get pubkey without double borrowing
    let pubkey: vector<u8> = vector::empty<u8>();
    let i = 0;
    let validators_len = vector::length(&chain.validators);
    print(&utf8(b" VALIDATORS LEN "));
    print(&validators_len);
    let found = false;
    print(&utf8(b" SENDER "));
    print(&signer::address_of(sender));
    print(&utf8(b" abc "));
    print(&chain.validators);
    let validator: Validator;
    while (i < validators_len) {
        let v = vector::borrow(&chain.validators, i);
        if (v.address == signer::address_of(sender)) {
            print(&v.address);
            print(&signer::address_of(sender));
            pubkey = v.pubkey;
            validator=*v;
            found = true;
            break;
        };
        i = i + 1;
    };
    assert!(found, ERROR_NOT_VALIDATOR);

    let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(pubkey);
    let signature = Crypto::new_signature_from_bytes(_signature);
    let verified = Crypto::signature_verify_strict(&signature, &pubkey_struct, message);
    assert!(verified, ERROR_INVALID_SIGNATURE);

    let pending = borrow_global_mut<Pending<T>>(STORAGE);
    let validated = borrow_global_mut<Validated<T>>(STORAGE);


    // Store event in both pending and chain storage
    handle_event<T, E, X>(
        sender,
        bcs::to_bytes(&signer::address_of(sender)),
        &mut pending.txs,
        &mut validated.txs,
        message,
    );
}

    // In the future allow anyone to add validator if they stake enough coins
    public entry fun allow_validator<T: store>(admin: &signer,validator_address: address, validator_pubkey: vector<u8>) acquires Chain {
        // Only admin can add validators
        print(&vector::length(&validator_pubkey));
        let chain = borrow_global_mut<Chain<T>>(STORAGE);

        // Check for duplicates
        let i = 0;
        let validators_len = vector::length(&chain.validators);
        while (i < validators_len) {
            let existing_validator = vector::borrow(&chain.validators, i);
            assert!(existing_validator.pubkey != validator_pubkey, ERROR_VALIDATOR_IS_ALREADY_ALLOWED);
            i = i + 1;
        };


        // Create and add validator struct
        let new_validator = Validator { address: validator_address, pubkey: validator_pubkey};
        vector::push_back(&mut chain.validators, new_validator);
    }


    ///
    /// VIEW
    /// 

    #[view]
    public fun get_chain_validators<T>(): vector<Validator> acquires Chain {
        let chain = borrow_global<Chain<T>>(STORAGE);
        chain.validators
    }

    #[view]
    public fun deserialize_message(message: vector<u8>): (DeserializedTX, u64 ) {
        let len = vector::length(&message);


        let event_id = from_bcs::to_u8(copy_range(&message, 0, 1)); // u8 is 1 bytes 
        let user_addr = copy_range(&message, 1, 33); // addresses are 32 bytes
        let vault_lend_rate = from_bcs::to_u64(copy_range(&message, 33, 41)); // u64 is 8 bytes
        let vault_borrow_rate = from_bcs::to_u64(copy_range(&message, 41,49)); // u64 is 8 bytes
        let amount = copy_range(&message, 49, 57); // u64 is 8 bytes
        let native_tx_hash = copy_range(&message, 57, 89); // tx hash is 32 bytes
        let vault_provider = String::utf8(copy_range(&message, 89, len)); // 
        (DeserializedTX 
        {
            native_tx_hash:native_tx_hash,
            event_type: convert_eventID_to_string(event_id),
            user: user_addr,
            vault_lend_rate: vault_lend_rate,
            vault_borrow_rate: vault_borrow_rate,
            amount: from_bcs::to_u64(amount),
            vault_provider: vault_provider,
        }, len)
    }

    /// In the future add pagination for txs by switching to smart table instead of table.
    #[view]
    public fun get_chain<T>(): Chain<T> acquires Chain {
        let chain = borrow_global<Chain<T>>(STORAGE);
        let _chain = Chain<T> {
            id: chain.id,
            name: chain.name,
            symbol: chain.symbol,
            validators: chain.validators,
        };
        _chain
    }



    ///
    /// HELPER
    /// 
    
    /// Helper function to get validator public key
    /// Returns `Some(pubkey)` if address is a validator, `None` otherwise
    public fun get_validator_pubkey<T: store>(validator_addr: address): vector<u8> acquires Chain {
        let chain = borrow_global<Chain<T>>(STORAGE);

        let i = 0;
        let validators_len = vector::length(&chain.validators);

        while (i < validators_len) {
            let v = vector::borrow(&chain.validators, i);
            if (v.address == validator_addr) {
                return (v.pubkey);
            };
            i = i + 1;
        };

        abort(ERROR_NOT_VALIDATOR)
    }


    //[DEPRECATED]
/*   public fun batch_is_tx_registered<T, E>(chain: &mut Chain<T>,txs: &vector<vector<u8>>): v {
        let chain = borrow_global_mut<Chain<T>>(ADMIN);
        let len = vector::length(&txs);
        while(len>0){
            let result = is_tx_registered(chain, vector::borrow(&txs, len-1));
        }
        is_tx_registered(chain, vector::borrow(&txs, len-1));
*/

    //[DEPRECATED]    
 /*   public fun is_tx_registered<T, E>(chain: &mut Chain<T>,native_tx_hash: &vector<u8>): bool {
        let timestamp = timestamp::now_seconds();
        let epoch_key = timestamp / 86400;

        if (type_info::type_name<E>() == type_info::type_name<DepositEvent>()) {
            if (!table::contains(&chain.deposits, epoch_key)) {
                return false;
            };
            let vec = table::borrow_mut(&mut chain.deposits, epoch_key);
            let len = vector::length(vec);
            let i = 0;
            while (i < len) {
                let event = vector::borrow(vec, i);
                if (event.native_tx_hash == *native_tx_hash) {
                    return true;
                };
                i = i + 1;
            };
            false

        } else if (type_info::type_name<E>() == type_info::type_name<RequestUnlockEvent>()) {
            if (!table::contains(&chain.request_unlocks, epoch_key)) {
                return false;
            };
            let vec = table::borrow_mut(&mut chain.request_unlocks, epoch_key);
            let len = vector::length(vec);
            let i = 0;
            while (i < len) {
                let event = vector::borrow(vec, i);
                if (event.native_tx_hash == *native_tx_hash) {
                    return true;
                };
                i = i + 1;
            };
            false

        } else if (type_info::type_name<E>() == type_info::type_name<UnlockEvent>()) {
            if (!table::contains(&chain.unlocks, epoch_key)) {
                return false;
            };
            let vec = table::borrow_mut(&mut chain.unlocks, epoch_key);
            let len = vector::length(vec);
            let i = 0;
            while (i < len) {
                let event = vector::borrow(vec, i);
                if (event.native_tx_hash == *native_tx_hash) {
                    return true;
                };
                i = i + 1;
            };
            false
        } else {
            false
        }
    }
*/
 
    public fun get_supra_bankers(): vector<address> acquires Chain {
        let chain = borrow_global_mut<Chain<Supra>>(STORAGE);
        let len = vector::length(&chain.validators);
        let vect = vector::empty<address>();
        let i = 0;
        while (i < len) {
            let validator = vector::borrow(&chain.validators, i);
            vector::push_back(&mut vect, validator.address);
            i = i + 1;
        };
        vect
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


fun handle_event<T, E, X: store>(signer: &signer, validator: vector<u8>, pending_table: &mut table::Table<vector<u8>, Quar>, validated_table: &mut table::Table<vector<u8>, Quar>, message: vector<u8>) acquires Caps {
    let quorum = storage::expect_u128(storage::viewConstant(utf8(b"QiaraChains"), utf8(b"QUARUM")));

    // Ensure message has enough bytes for all slices we take below.
    assert!(vector::length(&message) >= 73, ERROR_INVALID_MESSAGE);

    // Already validated?
    if (table::contains(validated_table, message)) {
        abort(ERROR_DUPLICATE_EVENT);
    };

    let vote_weight =  get_qiara_balance(from_bcs::to_address(validator));
    // Update pending validators
    // Update pending validators
    let count = if (table::contains(pending_table, message)) {
        let _quar = table::borrow_mut(pending_table, message);
        let exists = false;
        let len = vector::length(&_quar.validators);
        let i = 0;
        while (i < len) {
            let v = vector::borrow(&_quar.validators, i);
            if (v.validator == validator) {
                exists = true;
            };
            i = i + 1;
        };
        if (!exists) {
            let vote = ValidatorVote { validator: validator, weight: vote_weight };
            _quar.weight = _quar.weight + (vote_weight as u128);
            vector::push_back(&mut _quar.validators, vote);
        };
        _quar.weight
    } else {
        let validator_vote = ValidatorVote {validator: validator, weight: vote_weight};
        let vect = vector<ValidatorVote>[validator_vote];
        let quar = Quar {validators: vect, weight: (vote_weight as u128)};
        table::add(pending_table, copy message, quar);

        let event_id = from_bcs::to_u8(copy_range(&message, 0, 1));
        event::emit(ValidationEvent {
            chain_type: ChainTypes::convert_chainType_to_string<T>(),
            event_type: convert_eventID_to_string(event_id),
            validator: validator,
            message: message,
        });
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
        let event_id = from_bcs::to_u8(copy_range(&message, 0, 1));
        let user_addr = from_bcs::to_address(copy_range(&message, 1, 33));
        let lend_rate =  from_bcs::to_u64(copy_range(&message, 33, 41)); // u64 is 8 bytes
        let borrow_rate =  from_bcs::to_u64(copy_range(&message, 41,49)); // u64 is 8 bytes
        let amount = from_bcs::to_u64(copy_range(&message, 49, 57)); 
        //let vault_provider = copy_range(&message, 89, len); // 
        //let _native_tx_hash = copy_range(&message, 41, 73); // keep if youll use it later

        // >>> PROBABLE CRASH SITE BEFORE: make sure Caps exists <<<
        assert!(exists<Caps>(STORAGE), ERROR_CAPS_NOT_PUBLISHED);
        let cap = borrow_global<Caps>(STORAGE);

        // If these are needed later, keep; otherwise remove to avoid unused warnings.
        let _coin_cap = CoinDeployer::give_usercap(signer, &cap.coin_access);
        let _user_cap = Vaults::give_usercap(signer, &cap.vault_access);

        let even_type = convert_eventID_to_string(event_id);
        if(even_type == utf8(b"Deposit")){
            let coins = CoinDeployer::extract_to<E>(signer, _coin_cap, user_addr, amount);
            Vaults::bridge_deposit<E,T,X>(signer, &cap.vault_access, _user_cap, user_addr, amount, coins, lend_rate, borrow_rate);
        } else if(even_type == utf8(b"Request Unlock")){
         //   Vaults::request_unlock<E>(signer, user_addr, amount, &_user_cap);
        } else if(even_type == utf8(b"Unlock")){
         //   Vaults::unlock<E>(signer, user_addr, amount, &_user_cap);
        }  else{
            abort(ERROR_INVALID_MESSAGE);
        };
        let _validators = copy validators;
        event::emit(EventRegistered {
            chain_type: ChainTypes::convert_chainType_to_string<T>(),
            event_type: even_type,
            validator: copy validator,
            validators: validators.validators,
            recipient: user_addr,
            message: message,
            token_type: type_info::type_name<E>(),
            amount: amount,
            time: timestamp::now_seconds(),
        });
    };
}


    #[view]
    public fun is_validated_single<T>(message: vector<u8>): bool acquires Validated {
        let validated = borrow_global<Validated<T>>(STORAGE);
            if (table::contains(&validated.txs, message)) {
                return true
            } else {
                return false
            }
    }


    #[view]
    public fun is_validated<T>(messages: vector<vector<u8>>): vector<bool> acquires Validated {
        let validated = borrow_global<Validated<T>>(STORAGE);

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

