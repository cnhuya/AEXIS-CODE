module 0x0::SUIBITCOIN_VAULT1 {
    use sui::coin::{Self as coin};
    use sui::object;
    use sui::balance::{Self as balance, Balance, Supply};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::event;
    use std::type_name;
    use std::ascii::{Self, String};
    use sui::dynamic_field;
    use 0x0::SUIBITCOIN::SUIBITCOIN;
    use sui::object_table;
    use std::vector;
    use sui::table;
    use sui::hash;
    use sui::bcs;

    //
    // Errors
    //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_CANT_WITHDRAW_MORE_THAN_DEPOSIT: u64 = 2;
    const ERROR_USER_ALREADY_REGISTED_FOR_THIS_VAULT: u64 = 3;
    const ERROR_USER_NOT_REGISTERED: u64 = 4;
    const ERROR_USER_DIDNT_REQUEST_UNLOCK: u64 = 5;
    const ERROR_NOT_VALIDATOR: u64 = 6;
    const ERROR_ALREADY_APPROVED: u64 = 7;
    const ERROR_NOT_ENOUGH_APPROVALS: u64 = 8;
    const ERROR_ALREADY_FINALIZED: u64 = 9;
    const ERROR_NOT_ENOUGH_LIQUIDITY: u64 = 10;


    //
    // Vault & supporting types
    //
    public struct Vault has key, store {
        id: object::UID,
        owner: address,
        balance: Balance<SUIBITCOIN>, // total balance not allocated to requests
        requests: object_table::ObjectTable<vector<u8>, UnlockRequest>, // <-- add this
    }

    // Maybe completely remove in the near feature, lets see for future research about crosschain borrowing etc...
    public struct UserVaultPosition has key, store {
        id: object::UID,
        address: address,
  //      deposits: table::Table<address, u64>, // per-token or per-account deposits
  //      total_deposits: u128,            // fixed typo
    }


    public struct Admin has key, store {
        id: object::UID,
        addr: address,
    }

    public struct ValidatorSet has key, store {
        id: object::UID,
        addr: vector<address>,
        quarum: u8,
    }

    public struct UnlockRequest has key, store {
        id: UID,
        recipient: address,
        amount: u64,
        approvals: u64,
        approvers: vector<address>,
        finalized: bool,
    }

    //
    // Events
    //
    public struct DepositEvent has copy, drop {
        addr: address,
        amount: u64,
    }

    public struct UnlockEvent has copy, drop {
        addr: address,
        amount: u64,
    }

    public struct RequestUnlockEvent has copy, drop {
        requester: address,
        recipient: address,
        amount: u64,
        request_id: vector<u8>,
        vault_object: address,
    }

    public struct ObjectsInit has copy, drop {
        admin: address,
        vault: address,
        coin_type: String,
    }


    /// Publish a new ValidatorSet at VSET_ADDR. Only callable once.
    public fun create_validator_set(admin: &Admin, quarum: u8, ctx: &mut TxContext) {
        assert(admin.addr == ctx.sender(), ERROR_NOT_ADMIN);
        let validator_set =  ValidatorSet { id: object::new(ctx), addr: vector::empty<address>(), quarum };
        transfer::share_object(validator_set);
    }

    /// Add validator, only admin can call
    public entry fun add_validator(admin: &Admin,validator_set: &mut ValidatorSet, validator: address, ctx: &mut TxContext) {
        assert(admin.addr == ctx.sender(), ERROR_NOT_ADMIN);
        vector::push_back(&mut validator_set.addr, validator);
    }

    // Remove validator, only admin can call
    public entry fun remove_validator(admin: &Admin,validator_set: &mut ValidatorSet, validator: address, ctx: &mut TxContext) {
        assert(admin.addr == ctx.sender(), ERROR_NOT_ADMIN);
        assert!(vector::contains(&validator_set.addr, &validator));
        let (_, index) = vector::index_of(&validator_set.addr, &validator);
        vector::remove(&mut validator_set.addr, index);
    }


    fun is_validator(validator_set: &ValidatorSet, addr: address): bool {
        vector::contains(&validator_set.addr, &addr)
    }

    //
    // === Init vault & user ops (same as before) ===
    //
    fun init(ctx: &mut TxContext) {
        let admin = Admin { id: object::new(ctx), addr: ctx.sender() };
        let vault = Vault {id: object::new(ctx),owner: ctx.sender(),balance: balance::zero<SUIBITCOIN>(),requests: object_table::new<vector<u8>, UnlockRequest>(ctx),};

        let typename = type_name::into_string(type_name::get<SUIBITCOIN>());
        let idadmin = object::id_address(&admin);
        transfer::public_transfer(admin, ctx.sender());
        let idvault = object::id_address(&vault);
        transfer::share_object(vault);

        event::emit(ObjectsInit { admin: idadmin, vault: idvault, coin_type: typename });
    }

    public entry fun register_user(vault: &mut Vault, ctx: &mut TxContext) {
        let sender = ctx.sender();
        if (dynamic_field::exists_<address>(&vault.id, sender)) {
            abort ERROR_USER_ALREADY_REGISTED_FOR_THIS_VAULT;
        };
        let uvp = UserVaultPosition { id: object::new(ctx), address: sender, };
        dynamic_field::add(&mut vault.id, sender, uvp);
    }

    entry fun deposit(vault: &mut Vault,mut c: coin::Coin<SUIBITCOIN>, to: address, ctx: &mut TxContext) {
        let sender = ctx.sender();

        if (!dynamic_field::exists_<address>(&vault.id, sender)) {
            abort ERROR_USER_NOT_REGISTERED;
        };
        let c_value = coin::value(&c); // immutable borrow happens here
        let deposit_coin = coin::split(&mut c, c_value, ctx); // now only mutable borrow

        let deposit_balance = coin::into_balance(deposit_coin);
        let deposit_amount = balance::value(&deposit_balance);

        // Add to vault
        balance::join(&mut vault.balance, deposit_balance);

        // Return leftover coin (should be zero)
        transfer::public_transfer(c, sender);

        // Emit event with numeric amount
        event::emit(DepositEvent { addr: to, amount: deposit_amount });
    }




    public entry fun unlock(validator_set: &ValidatorSet,vault: &mut Vault,recipient: address,amount: u64, time: u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);

        // Compute deterministic request_id from vault + recipient + amount
        let mut vect = vector::empty<u8>();
        vector::append(&mut vect,bcs::to_bytes(&vault.id));
        vector::append(&mut vect,bcs::to_bytes(&recipient));
        vector::append(&mut vect,bcs::to_bytes(&amount));
        vector::append(&mut vect,bcs::to_bytes(&time));
        let req_id = hash::keccak256(&vect);

        if (!object_table::contains(&vault.requests, req_id)) {
            // Create a new unlock request
            let req = UnlockRequest {
                id: object::new(ctx), // still need an object ID internally
                recipient,
                amount,
                approvals: 0,
                approvers: vector::empty(),
                finalized: false,
            };

            object_table::add(&mut vault.requests, req_id, req);

            event::emit(RequestUnlockEvent {
                requester: sender,
                recipient,
                amount,
                request_id: req_id,
                vault_object: object::uid_to_address(&vault.id),
            });
        } else {
            // Handle approval path
            assert!(is_validator(validator_set, sender), ERROR_NOT_VALIDATOR);

            let req = object_table::borrow_mut(&mut vault.requests, req_id);

            assert!(!vector::contains(&req.approvers, &sender), ERROR_ALREADY_APPROVED);
            vector::push_back(&mut req.approvers, sender);
            req.approvals = req.approvals + 1;

            if (req.approvals >= 5 && !req.finalized) {
                req.finalized = true;

               assert!(balance::value(&vault.balance) >= req.amount, ERROR_NOT_ENOUGH_LIQUIDITY);

                let release_balance = balance::split(&mut vault.balance, req.amount);
                let release_coin = coin::from_balance(release_balance, ctx);
                transfer::public_transfer(release_coin, req.recipient);

                event::emit(UnlockEvent {
                    addr: req.recipient,
                    amount: req.amount,
                });
            }
        }
    }
}
