module QiaraMultiAssetVaultV1::QiaraMultiAssetVaultV1 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use std::string::{Self, String};
    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};

    use QiaraVariablesV1::QiaraVariablesV1::{Self as vars}; 

// --- Errors ---
    const ENotSupported: u64 = 0;
    const EInsufficientPermission: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EAssetNotMatchedByRegistry: u64 = 3;
    const EDelegatorAlreadySet: u64 = 4;
    const EDelegatorNotSet: u64 = 5;

// --- Objects ---

    public struct VaultInfo has store, copy, drop {
        vault_id: ID,
        admin_cap_id: ID,
    }

    public struct GlobalConfig has key {
        id: UID,
        admin_address: address,
        delegator_address: Option<address>,
        // New: Table to track all vaults by name
        vaults: Table<String, VaultInfo> 
    }

    public struct AdminCap has key, store { 
        id: UID,
        vault_id: ID 
    }

    public struct Vault has key {
        id: UID,
        provider_name: String,
    }

    public struct ReserveKey<phantom T> has copy, drop, store {}

    public struct AllowanceKey has copy, drop, store {
        user: address,
        token_type: TypeName
    }

    public struct SupportedTokenKey has copy, drop, store {
        token_type: TypeName
    }

// --- Initialization ---

    fun init(ctx: &mut TxContext) {
        let config = GlobalConfig {
            id: object::new(ctx),
            admin_address: tx_context::sender(ctx), // You are the initial admin
            delegator_address: option::none(),     // Starts as 0x0 (None)
            vaults: table::new<String, VaultInfo>(ctx)
        };
        transfer::share_object(config);
    }

// --- Governance ---

    /// One-time function to set the permanent Delegator (ZK-Verifier) address
    public entry fun set_permanent_delegator(config: &mut GlobalConfig, delegator: address, ctx: &TxContext) {
        // 1. Only the original admin can call this
        assert!(tx_context::sender(ctx) == config.admin_address, ENotAuthorized);
        
        // 2. Ensure it is currently "0x0" (None)
        assert!(option::is_none(&config.delegator_address), EDelegatorAlreadySet);

        // 3. Lock it in forever
        option::fill(&mut config.delegator_address, delegator);
    }

// --- Permissionless Factory ---

    public entry fun create_vault(config: &GlobalConfig,provider_name: String, ctx: &mut TxContext) {
        // Ensure the delegator has been set before allowing vault creation
        assert!(option::is_some(&config.delegator_address), EDelegatorNotSet);
            
        let delegator = *option::borrow(&config.delegator_address);

        let vault_uid = object::new(ctx);
        let vault_id = object::uid_to_inner(&vault_uid);

        let admin_cap = AdminCap { id: object::new(ctx),vault_id };

        let vault = Vault {id: vault_uid,provider_name,};

            // Automatically sends the cap to the address stored in Config
        transfer::public_transfer(admin_cap, delegator);
        transfer::share_object(vault);
    }

// --- Permissionless Asset Listing ---

    /// Anyone can call this. It checks the governance-controlled registry 
    /// to see if the token is valid for this provider.
    public entry fun list_new_token<T>(vault: &mut Vault, registry: &vars::Registry) {
        let token_type = type_name::get<T>();
        
        // 1. Convert ASCII TypeName string to a UTF-8 String
        let ascii_type_name = type_name::into_string(token_type);
        let mut asset_key = string::from_ascii(ascii_type_name); 

        // 2. Now you can append UTF-8 strings
        string::append(&mut asset_key, string::utf8(b"_"));
        string::append(&mut asset_key, vault.provider_name);

        // 3. Query the registry
        // Note: I added 'registry' to the parameters as 'get_variable' likely needs the object
        let asset_bytes = vars::get_variable(registry, string::utf8(b"QiaraSuiAssets"), asset_key);
        
        // 4. In Move, variables usually return vector<u8>. 
        // If you're storing the type string in the registry, you verify it here.
        assert!(!vector::is_empty(&asset_bytes), EAssetNotMatchedByRegistry);
        
        df::add(&mut vault.id, SupportedTokenKey { token_type }, true);
    }
    // --- Administrative Functions ---

    /// Only the Delegator (holding AdminCap) can grant specific withdrawal rights
    public entry fun grant_withdrawal_permission<T>(admin: &AdminCap, vault: &mut Vault, user: address, amount: u64) {
        assert!(admin.vault_id == object::id(vault), ENotAuthorized);
        internal_grant<T>(vault, user, amount);
    }

// --- User Functions ---
    public entry fun deposit<T>(vault: &mut Vault, coin: Coin<T>, ctx: &mut TxContext) {
        let token_type = type_name::get<T>();
        assert!(df::exists_(&vault.id, SupportedTokenKey { token_type }), ENotSupported);

        let amount = coin::value(&coin);
        let sender = tx_context::sender(ctx);

        let reserve_key = ReserveKey<T> {};
        if (!df::exists_(&vault.id, reserve_key)) {
            df::add(&mut vault.id, reserve_key, balance::zero<T>());
        };
        let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
        balance::join(reserve, coin::into_balance(coin));

        update_allowance<T>(vault, sender, amount);
    }

    public entry fun claim_profit<T>(vault: &mut Vault, amount: u64, receiver: address, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let token_type = type_name::get<T>();
        let allowance_key = AllowanceKey { user: sender, token_type };

        assert!(df::exists_(&vault.id, allowance_key), EInsufficientPermission);
        let allowance = df::borrow_mut<AllowanceKey, u64>(&mut vault.id, allowance_key);
        assert!(*allowance >= amount, EInsufficientPermission);
        
        *allowance = *allowance - amount;

        let reserve_key = ReserveKey<T> {};
        let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
        let withdrawn_balance = balance::split(reserve, amount);

        transfer::public_transfer(coin::from_balance(withdrawn_balance, ctx), receiver);
    }

// --- Internal Helpers ---
    fun internal_grant<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        assert!(df::exists_(&vault.id, SupportedTokenKey { token_type }), ENotSupported);
        update_allowance<T>(vault, user, amount);
    }

    fun update_allowance<T>(vault: &mut Vault, user: address, amount: u64) {
        let token_type = type_name::get<T>();
        let key = AllowanceKey { user, token_type };
        if (df::exists_(&vault.id, key)) {
            let current = df::borrow_mut<AllowanceKey, u64>(&mut vault.id, key);
            *current = *current + amount;
        } else {
            df::add(&mut vault.id, key, amount);
        };
    }
}