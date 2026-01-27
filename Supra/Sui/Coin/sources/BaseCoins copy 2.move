module 0x0::SUIBITCOIN_VAULT {
    use sui::coin::{Self as coin, Coin, value, put, take, zero, from_balance, into_balance};
    use sui::object;
    use sui::balance::{Self as balance, Balance, Supply};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::event;
    use std::type_name;
    use std::ascii::{Self, String};
    use sui::dynamic_field;
    use 0x0::SUIBITCOIN::SUIBITCOIN;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_CANT_WITHDRAW_MORE_THAN_DEPOSIT: u64 = 2;
    const ERROR_USER_ALREADY_REGISTED_FOR_THIS_VAULT: u64 = 3;
    const ERROR_USER_NOT_REIGSTERED: u64 = 4;
    const ERROR_USER_DIDNT_REQUEST_UNLOCK: u64 = 5;

    public struct Vault has key, store {
        id: object::UID,
        owner: address,
        balance: Balance<SUIBITCOIN>,
    }

    
    public struct UserVaultPosition has key, store {
        id: object::UID,
        address: address,
        balance: u64,
        requsted_for_unlock: u64,
    }

    public struct Admin has key, store {
        id: object::UID,
        addr: address,
    }

    public struct DepositEvent has copy, drop {
        addr: address,
        amount: u64,
    }

    public struct UnlockEvent has copy, drop {
        addr: address,
        amount: u64,
    }

    public struct RequestUnlockEvent has copy, drop {
        addr: address,
        amount: u64,
        admin_object: address,
        user_vault_object: address,
        vault_object: address,
    }

    public struct ObjectsInit has  copy, drop {
        admin: address,
        vault: address,
        coin_type: String,
    }



    fun init(ctx: &mut TxContext) {
        let admin = Admin { id: object::new(ctx), addr: ctx.sender() };
        let vault = Vault { id: object::new(ctx), owner: ctx.sender(), balance: balance::zero<SUIBITCOIN>() };

        // Transfer objects to caller
        let typename = type_name::into_string(type_name::get<SUIBITCOIN>());
        let idadmin =  object::id_address(&admin);
        transfer::public_transfer(admin, ctx.sender());
        let idvault =  object::id_address(&vault);
        transfer::share_object(vault);

        // Emit event with UIDs
        event::emit(ObjectsInit { admin: idadmin, vault: idvault, coin_type: typename });
    }


    public entry fun register_user(vault: &mut Vault, ctx: &mut TxContext) {
        let sender = ctx.sender();

        // Check if already registered
        if (dynamic_field::exists_<address>(&vault.id, sender)) {
            abort ERROR_USER_ALREADY_REGISTED_FOR_THIS_VAULT
        };

        let uvp = UserVaultPosition { id: object::new(ctx), address: sender, balance: 0, requsted_for_unlock: 0 };

        // Attach UserVaultPosition to vault registry
        dynamic_field::add(&mut vault.id, sender, uvp);
    }

    public entry fun deposit(
        vault: &mut Vault,
        mut c: Coin<SUIBITCOIN>,
        address: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let sender = ctx.sender();

        // Ensure the user is registered
        if (!dynamic_field::exists_<address>(&vault.id, sender)) {
            abort ERROR_USER_NOT_REIGSTERED
        };

        // Borrow the user's vault position
        let uvp_ref = dynamic_field::borrow_mut<address, UserVaultPosition>(&mut vault.id, sender);

        // Update balances
        let deposit_coin = coin::split(&mut c, amount, ctx);
        let deposit_balance = coin::into_balance(deposit_coin);
        balance::join(&mut vault.balance, deposit_balance);
        uvp_ref.balance = uvp_ref.balance + amount;

        // Return leftover coin to sender
        transfer::public_transfer(c, sender);

        // Emit event
        event::emit(DepositEvent { addr: sender, amount });
    }

    //public entry fun request_unlock(admin: &Admin, mut uservault: UserVaultPosition, vault: &mut Vault,recipient: address,amount: u64,ctx: &mut TxContext) {
    public entry fun request_unlock(admin: &Admin, vault: &mut Vault,amount: u64,ctx: &mut TxContext) {
        let uvp_ref = dynamic_field::borrow_mut<address, UserVaultPosition>(&mut vault.id, ctx.sender());
        
        assert!(amount <= uvp_ref.balance, ERROR_CANT_WITHDRAW_MORE_THAN_DEPOSIT );

        let idadmin =  object::id_address(admin);
        let uservault =  object::id_address(uvp_ref);
        let idvault =  object::id_address(vault);

        uvp_ref.requsted_for_unlock = uvp_ref.requsted_for_unlock + amount;

        event::emit(RequestUnlockEvent { addr: ctx.sender(), amount, admin_object:idadmin, user_vault_object:uservault,  vault_object:idvault });
    }

    //public entry fun unlock(admin: &Admin, mut uservault: UserVaultPosition, vault: &mut Vault,recipient: address,amount: u64,ctx: &mut TxContext) {

    public entry fun unlock(admin: &Admin, vault: &mut Vault,recipient: address,ctx: &mut TxContext) {
        assert!(ctx.sender() == admin.addr, ERROR_NOT_ADMIN);

        // Ensure vault has enough balance

        // Split the balance and convert to Coin
        let amount = uvp_ref.requsted_for_unlock;

        let withdrawn_balance = balance::split(&mut vault.balance, amount);
        let coin_to_send = from_balance(withdrawn_balance, ctx);

        let uvp_ref = dynamic_field::borrow_mut<address, UserVaultPosition>(&mut vault.id, recipient);

        assert!(amount <= uvp_ref.requsted_for_unlock, ERROR_USER_DIDNT_REQUEST_UNLOCK );
        assert!(amount <= uvp_ref.balance, ERROR_CANT_WITHDRAW_MORE_THAN_DEPOSIT );

        uvp_ref.requsted_for_unlock = 0;
        uvp_ref.balance = uvp_ref.balance - amount;

       // uservault.balance = uservault.balance - amount;
       // transfer::public_transfer(uservault, ctx.sender());

        transfer::public_transfer(coin_to_send, recipient);

        event::emit(UnlockEvent { addr: recipient, amount });
    }

    public fun balance(v: &Vault): u64 {
        balance::value<SUIBITCOIN>(&v.balance) // get u64 value
    }
}
