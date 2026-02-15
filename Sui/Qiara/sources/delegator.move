module Qiara::QiaraDelegatorV1 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::groth16;
    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};
    use sui::event;
    use sui::bcs;
    use std::string::{Self, String};
    use std::vector;
    use sui::dynamic_field as df;
    use Qiara::QiaraExtractorV1::{Self as extractor};
    use Qiara::QiaraVariablesV1::{Self as vars}; 
    // Your VK here (keep as is for now)
    const FULL_VK: vector<u8> = x"e2f26dbea299f5223b646cb1fb33eadb059d9407559d7441dfd902e3a79a4d2dabb73dc17fbc13021e2471e0c08bd67d8401f52b73d6d07483794cad4778180e0c06f33bbc4c79a9cadef253a68084d382f17788f885c9afd176f7cb2f036789edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e191160d4d6288ed6209546f23e08f5f20215a76fe911cabcebe3ff05c4426a5323df985dd6ceb2cddb3ba707c16e35a52de321bf754584d7e5b00ade2854d9a39d0900000000000000a8b2914b2397dfb02594a783e374b17b8502a2be3a16cf73c55b99741aeba08b4b7db1eca1944113e87ce0ea4a1d06de2355b097ac0bbb62d2a74373912bae9b1bf51c1bc32225fdfd60df681a7586500b312cc9ab15d81aa8e5a6c9c03b3e1d4801388fe035397be0d810c3561ae51d1412ab95ec2139cfeab4d30935aa2b2d14d17ed082157ce49533d369f6e03ca27ae7349a7fe0af42c5599114dd2a7283ad35db6f67a48096427d0f443e3ccbdfcf41d6b59ec2ca05d01d8fccaac599076a5869cf15aea3380627131d27dfff4ce02e7fff3590c4814b1707410bc04d1c88b7a440151c73770dbee8fc5fffe1605752c9e7f5695601f3df7e4910c71e20e3010d5e049c7c3a2cd8df0e08142b0203861d07f3016872b76d9eac15fa4b05";
    
    const EInvalidProof: u64 = 0;
    const EInvalidPublicInputs: u64 = 1;
    const ENullifierUsed: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EWrongProviderProvided: u64 = 4;
    const EProviderAlreadyExists: u64 = 5;
    const EUnsupportedProviderName: u64 = 6;
    const EInsufficientPermission: u64 = 7;
    const ENotSupported: u64 = 8;
    const EWrongChainId: u64 = 9;

    const SUI_CHAIN_ID: u64 = 103;


    // Events
    public struct TokenListed has copy, drop {
        vault_id: ID,
        token_type: String,
        provider_name: String
    }

    public struct SupportedTokenKey has copy, drop, store {
        token_type: TypeName
    }

    public struct VaultInfo has store, copy, drop {
        addr: address,
        vault_id: ID,
        admin_cap_id: ID,
    }

    public struct AdminCap has key, store { 
        id: UID,
        vault_id: ID 
    }

    public struct Vault has key {
        id: UID,
        provider_name: String,
        addr: address,
    }

    public struct ReserveKey<phantom T> has copy, drop, store {}

    public struct Nullifiers has key, store {
        id: UID,
        table: table::Table<u256, bool>,
    }

    public struct ProviderManager has key {
        id: UID,
        vaults: Table<String, VaultInfo> 
    }

    fun init(ctx: &mut TxContext) {
        let nullifiers = Nullifiers { id: object::new(ctx), table: table::new(ctx) };
        transfer::share_object(nullifiers);

        let manager = ProviderManager { id: object::new(ctx), vaults: table::new(ctx) };
        transfer::share_object(manager);
    }

    public entry fun create_vault(config: &mut ProviderManager, registry: &vars::Registry, provider_name: String, ctx: &mut TxContext) {
        
        let provider_interface_module_address = vars::get_variable_to_address(registry, string::utf8(b"QiaraSuiProviders"), provider_name);

        // Check if a provider already exists to prevent overwriting
        assert!(!table::contains(&config.vaults, provider_name), EProviderAlreadyExists);

        // 2. Create the Vault
        let vault_uid = object::new(ctx);
        let vault_id = object::uid_to_inner(&vault_uid);
        let vault = Vault {id: vault_uid, provider_name: provider_name, addr: provider_interface_module_address,};

        // 3. Create the AdminCap
        let cap_uid = object::new(ctx);
        let admin_cap_id = object::uid_to_inner(&cap_uid);
        let admin_cap = AdminCap { id: cap_uid,vault_id };

        // 4. Store the information in GlobalConfig
        let info = VaultInfo {
            addr: provider_interface_module_address,
            vault_id,
            admin_cap_id,};
        table::add(&mut config.vaults, provider_name, info);

        // 5. Transfer and Share
        transfer::public_transfer(admin_cap, provider_interface_module_address);
        transfer::share_object(vault);
    }

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
        
        df::add(&mut vault.id, SupportedTokenKey { token_type }, true);

        event::emit(TokenListed {
            vault_id: object::id(vault),
            token_type: string::from_ascii(type_name::get_module(&type_name::get<T>())),
            provider_name: vault.provider_name,
        });

    }

    /// Adds funds to the vault. 
    /// If the token hasn't been deposited before, it initializes the reserve.
    public fun increase_reserve<T>(vault: &mut Vault, coin: Coin<T>) {
        let reserve_key = ReserveKey<T> {};
        let coin_balance = coin::into_balance(coin);

        if (!df::exists_(&vault.id, reserve_key)) {
            // Initialize the reserve field if it doesn't exist
            df::add(&mut vault.id, reserve_key, coin_balance);
        } else {
            // Borrow existing and join
            let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
            balance::join(reserve, coin_balance);
        }
    }

    /// Removes funds from the vault.
    /// Added an assertion to ensure the reserve actually exists and has enough funds.
    public fun decrease_reserve<T>(vault: &mut Vault, amount: u64): Balance<T> {
        let reserve_key = ReserveKey<T> {};
        
        // 1. Critical Check: Does the reserve even exist?
        // If we don't check this, df::borrow_mut will abort with code 1.
        assert!(df::exists_(&vault.id, reserve_key), ENotSupported);

        let reserve = df::borrow_mut<ReserveKey<T>, Balance<T>>(&mut vault.id, reserve_key);
        
        // 2. Critical Check: Is there enough in the reserve?
        // balance::split will abort automatically if amount > balance, 
        // but a custom error is clearer for debugging.
        assert!(balance::value(reserve) >= amount, EInsufficientPermission);

        balance::split(reserve, amount)
    }

    public fun verifyZK(config: &ProviderManager, nullifiers: &mut Nullifiers, public_inputs: vector<u8>,proof_points: vector<u8>): (address, u64) {
        let curve = groth16::bn254();

        // 2. Verify the proof
        let curve = groth16::bn254();
        let pvk = groth16::prepare_verifying_key(&curve, &FULL_VK);
        let pi_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let pp_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &pi_struct, &pp_struct), EInvalidProof);

        // 3. Nullification Logic - Avoiding re-use
        let nullifier = extractor::build_nullifier(&public_inputs);

        if(table::contains(&nullifiers.table, nullifier)) {
            abort ENullifierUsed;
        };  
        table::add(&mut nullifiers.table, nullifier, true);

        // 4. Extract values
        let user = extractor::extract_user_address(&public_inputs);
        let amount = extractor::extract_amount(&public_inputs);
        let vault_provider = extractor::extract_provider(&public_inputs);
        let chain_id = extractor::extract_chain_id(&public_inputs);
        assert!(chain_id == SUI_CHAIN_ID, EWrongChainId);

        // 5. Safety check, if provider is supported
        assert!(table::contains(&config.vaults, vault_provider), EWrongProviderProvided);

        // 6. Grant withdrawal permission
        return (user, amount)
    }


    public fun borrow_id(vault: &Vault): &UID {
        &vault.id
    }
    public fun borrow_id_mut(vault: &mut Vault): &mut UID {
        &mut vault.id
    }
    public fun is_token_supported<T>(vault: &Vault): bool {
        let token_type = type_name::get<T>();
        df::exists_(&vault.id, SupportedTokenKey { token_type })
    }

}