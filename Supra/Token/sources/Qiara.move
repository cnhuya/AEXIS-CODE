module dev::QiaraTestV29 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::timestamp;
    use supra_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use supra_framework::dispatchable_fungible_asset;
    use supra_framework::primary_fungible_store;
    use supra_framework::function_info;
    use supra_framework::object::{Self, Object};
    use std::string::{Self as string, String, utf8};
    
    use dev::QiaraStorageV21::{Self as storage};
    use dev::QiaraCapabilitiesV21::{Self as capabilities};

    const ADMIN: address = @dev;

    const ERROR_NOT_OWNER: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_CLAIMING: u64 = 2;
    const ERROR_BLACKLISTED: u64 = 3;
    const ERROR_PAUSED: u64 = 4;

    const SECONDS_IN_MONTH: u64 = 2_592_000;
    const U64_MAX: u64 = 18_446_744_073_709_551_615;
    const INIT_SUPPLY: u64 = 1_000_000_000_000;
    const ASSET_SYMBOL: vector<u8> = b"QiaraT29";
    const DECIMALS_N: u64 = 1_000_000;    

    // Token Type
    struct Qiara has drop, store, key {}

    struct CreationTime has key{
        time: u64,
    }

    struct ManagedFungibleAsset has key {
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    // reserve for inflation. 
    struct SupplyVault has key, store {
        vault: Object<FungibleStore>,
        last_claimed: u64,
    }


    struct Supply has key, store{
        innitial_supply: u128,
        circulating_supply: u128,
        burned_supply: u128,
        innitial_vault_supply: u128,
        vault_supply: u128,
        claimable: u128,
    }

    struct Features has key, store{
        inflation: u64,
        base_inflation: u64,
        inflation_debt: u64,
        creation_time: u64,
        month: u64,
        base_burn_fee: u64,
        burn_fee_increase: u64,
        burn_fee: u64,
        treasury_fee: u64,
        treasury_receipent: address,
        transferable: bool,
    }

    struct CoinMetadata has key, store{
        address: address,
        name: String,
        symbol: String, 
        decimals: u8,
        decimals_scale: u64,
        icon_uri: String,
        project_uri: String,
        is_paused: bool, 
    }

    struct CoinData has key{
        supply: Supply,
        features: Features,
        metadata: CoinMetadata
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer)  {
        let constructor_ref = &object::create_named_object(admin, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(b"Qiara Token"),
            utf8(ASSET_SYMBOL), /* symbol */
            6, 
            utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/icon.webp"), /* icon */
            utf8(b"https://x.com/QiaraProtocol"), /* project */
        );
        let asset = get_metadata();
        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);

        let metadata_object_signer = object::generate_signer(constructor_ref);

        let vault_fa = fungible_asset::mint(&mint_ref, U64_MAX-INIT_SUPPLY);
        let init_fa = fungible_asset::mint(&mint_ref, INIT_SUPPLY);


        let asset_address = object::create_object_address(&ADMIN, ASSET_SYMBOL);
        let obj_adress = object::address_to_object<Metadata>(asset_address);


        let sign_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(admin),asset);

        let vault_store = fungible_asset::create_store(constructor_ref, obj_adress);
        
        move_to(admin, SupplyVault { vault: vault_store, last_claimed: timestamp::now_seconds() });

        move_to(admin, CreationTime {time: timestamp::now_seconds() });


        // Override the deposit and withdraw functions which mean overriding transfer.
        // This ensures all transfer will call withdraw and deposit functions in this module
        // and perform the necessary checks.
        // This is OPTIONAL. It is an advanced feature and we don't NEED a global state to pause the FA coin.
        let deposit = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTestV29"),
            string::utf8(b"deposit"),
        );
        let withdraw = function_info::new_function_info(
            admin,
            string::utf8(b"QiaraTestV29"),
            string::utf8(b"withdraw"),
        );
        dispatchable_fungible_asset::register_dispatch_functions(
            constructor_ref,
            option::some(withdraw),
            option::some(deposit),
            option::none(),
        );

        deposit(sign_wallet,init_fa,&transfer_ref);
        deposit(vault_store,vault_fa,&transfer_ref);
        move_to(&metadata_object_signer,ManagedFungibleAsset { transfer_ref, burn_ref }); // <:!:initialize

    }

    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------
    /// Deposit tokens into an arbitrary FungibleStore (ERC-20 transferToVault)
    public entry fun deposit_to_store(sender: &signer,store: Object<FungibleStore>,amount: u64) acquires ManagedFungibleAsset, CreationTime {
        assert!(!capabilities::assert_wallet_capability(signer::address_of(sender), utf8(b"QiaraToken"), utf8(b"BLACKLIST")), ERROR_BLACKLISTED);
        let asset = get_metadata();
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let transfer_ref = &managed.transfer_ref;

        let from_wallet = primary_fungible_store::primary_store(signer::address_of(sender), asset);

        let fa = withdraw(from_wallet, amount, transfer_ref);
        deposit(store, fa, transfer_ref);
    }


    /// Withdraw tokens back from a FungibleStore into the callers account (ERC-20 withdraw)
    public entry fun withdraw_from_store(sender: &signer,store: Object<FungibleStore>,amount: u64) acquires ManagedFungibleAsset, CreationTime {
        assert!(!capabilities::assert_wallet_capability(signer::address_of(sender), utf8(b"QiaraToken"), utf8(b"BLACKLIST")), ERROR_BLACKLISTED);
        let asset = get_metadata();
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let transfer_ref = &managed.transfer_ref;

        let fa = withdraw(store, amount, transfer_ref);

        let caller_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),asset);
        deposit(caller_wallet, fa, transfer_ref);
    }


    /// Deposit function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun deposit<T: key>(store: Object<T>,fa: FungibleAsset,transfer_ref: &TransferRef,) {
        assert_not_paused();
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }

    /// Withdraw function override to ensure that the account is not denylisted and the FA coin is not paused.
    /// OPTIONAL
    public fun withdraw<T: key>(store: Object<T>,amount: u64,transfer_ref: &TransferRef): FungibleAsset acquires CreationTime {
        assert_not_paused();
        calculate_fees(store, amount, transfer_ref)
    }

    public entry fun transfer(user: &signer, to: address, amount: u64) acquires ManagedFungibleAsset, CreationTime {
        assert_not_paused();
        assert!(!capabilities::assert_wallet_capability(signer::address_of(user), utf8(b"QiaraToken"), utf8(b"TRANSFER_BLACKLIST")), ERROR_BLACKLISTED);
        let asset = get_metadata();
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let transfer_ref = &managed.transfer_ref;

        let from_wallet = primary_fungible_store::primary_store(signer::address_of(user), asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = withdraw(from_wallet, amount, transfer_ref);
        deposit(to_wallet, fa, transfer_ref);
    }

    /// Burn fungible assets directly from the caller's own account.
    /// Anyone can call this to burn their own tokens.
    public entry fun burn(caller: &signer, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let wallet = primary_fungible_store::primary_store(signer::address_of(caller), asset);
        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let fa = fungible_asset::withdraw_with_ref(&managed.transfer_ref, wallet, amount);
        fungible_asset::burn(&managed.burn_ref, fa);
    }


    public entry fun claim_inflation(claimer: &signer) acquires SupplyVault, ManagedFungibleAsset, CreationTime {
        assert!(capabilities::assert_wallet_capability(signer::address_of(claimer), utf8(b"QiaraToken"), utf8(b"INFLATION_CLAIM")), ERROR_NOT_AUTHORIZED_FOR_CLAIMING);
        let asset = get_metadata();

        let managed = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let seconds_per_year = 31_536_000; // 365*24*60*60
        let claimable_amount = claimable();

        // Time since last claim
        let vault = borrow_global_mut<SupplyVault>(ADMIN);
        let delta_seconds = timestamp::now_seconds() - vault.last_claimed;

        // Calculate claimable amount proportionally

        let fa = withdraw(vault.vault,(claimable_amount as u64),&managed.transfer_ref,);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(signer::address_of(claimer),asset
        );

        deposit(to_wallet, fa, &managed.transfer_ref,);
        vault.last_claimed = timestamp::now_seconds();
    }


    // --------------------------
    // HELPERS
    // --------------------------
    /// Assert that the FA coin is not paused.
    fun assert_not_paused() {
        assert!(!storage::expect_bool(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"PAUSED"))), ERROR_PAUSED);
    }

    /// Borrow the immutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(owner: &signer,asset: Object<Metadata>,): &ManagedFungibleAsset acquires ManagedFungibleAsset {assert!(object::is_owner(asset, signer::address_of(owner)), ERROR_NOT_OWNER);borrow_global<ManagedFungibleAsset>(object::object_address(&asset))}

    fun calculate_fees<T: key>(store: Object<T>,amount: u64,transfer_ref: &TransferRef): FungibleAsset acquires CreationTime {
        let asset = get_metadata();
        let month = get_month();

        let burn_fee_bps = get_burn_fee() + get_burn_fee_increase() * month;
        let treasury_fee_bps = get_treasury_fee();

        // scale denominator = 100_000_000 (because 1% = 1_000_000, so 100% = 100_000_000)
        let scale = 100_000_000;

        let burn_amount = (amount * burn_fee_bps) / scale;
        let treasury_amount = (amount * treasury_fee_bps) / scale;
        let transfer_amount = amount - (burn_amount + treasury_amount);

        let treasury_store = primary_fungible_store::ensure_primary_store_exists(
            get_treasury_receipent(),
            asset
        );

        let burn_wallet = primary_fungible_store::ensure_primary_store_exists(@0x0, asset);
        let burn_fa = fungible_asset::withdraw_with_ref(transfer_ref, store, burn_amount);
        deposit(burn_wallet, burn_fa, transfer_ref);

        let treasury_fa = fungible_asset::withdraw_with_ref(transfer_ref, store, treasury_amount);
        deposit(treasury_store, treasury_fa, transfer_ref);

        fungible_asset::withdraw_with_ref(transfer_ref, store, transfer_amount)
    }

    // --------------------------
    // VIEWS
    // --------------------------
    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_vault(): Object<FungibleStore>  acquires SupplyVault{
        let vault = borrow_global<SupplyVault>(ADMIN);
        vault.vault
    }

    #[view]
    public fun get_burned_supply(): u64 {
       fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(@0x0, get_metadata()))
    }

    #[view]
    public fun get_vault_balance(): u64 acquires SupplyVault {
        let vault = borrow_global<SupplyVault>(ADMIN);
        fungible_asset::balance(vault.vault)
    }

    #[view]
    public fun get_coin_metadata(): CoinMetadata {
        let metadata = get_metadata();
        CoinMetadata{
            address: object::create_object_address(&ADMIN, ASSET_SYMBOL),
            name: fungible_asset::name(metadata),
            symbol: fungible_asset::symbol(metadata),
            decimals: fungible_asset::decimals(metadata),
            decimals_scale: DECIMALS_N,
            icon_uri: fungible_asset::icon_uri(metadata),
            project_uri: fungible_asset::project_uri(metadata),
            is_paused: storage::expect_bool(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"PAUSED"))),
        }
    }

    #[view]
    public fun get_inflation(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION")))
    }

    #[view]
    public fun is_transferable(): bool {
        storage::expect_bool(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"TRANSFERABLE")))
    }

    #[view]
    public fun get_inflation_debt(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT")))
    }

    #[view]
    public fun get_burn_fee(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE")))
    }

    #[view]
    public fun get_burn_fee_increase(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_INCREASE")))
    }

    #[view]
    public fun get_treasury_fee(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"TREASURY_FEE")))
    }

    #[view]
    public fun get_treasury_receipent(): address {
        storage::expect_address(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"TREASURY_RECEIPENT")))
    }

    #[view]
    public fun get_month(): u64  acquires CreationTime{
        let creation_time = borrow_global<CreationTime>(ADMIN);
        ((timestamp::now_seconds() - creation_time.time ) / SECONDS_IN_MONTH)
    }

    #[view]
    public fun get_creation_time(): u64 acquires CreationTime{
        let creation_time = borrow_global<CreationTime>(ADMIN);
        creation_time.time
    }

    #[view]
    public fun claimable(): u128 acquires SupplyVault {
        let circulating_supply = circulating_supply();
        let vault = borrow_global_mut<SupplyVault>(ADMIN);

        // Seconds in a year
        let seconds_per_year = 31_536_000; // 365*24*60*60

        // Time since last claim
        let delta_seconds = timestamp::now_seconds() - vault.last_claimed;

        // Calculate claimable amount proportionally
        (circulating_supply * (get_inflation() as u128) * (delta_seconds as u128)) / ((seconds_per_year as u128) * 10_000)
    }


    #[view]
    public fun circulating_supply(): u128 acquires SupplyVault {
        let vault_balance = (get_vault_balance() as u128); // convert to u128 for safety
        let total_supply_opt = fungible_asset::supply(get_metadata());

        let total_supply = option::borrow(&total_supply_opt);

        // Now subtract safely
        (*total_supply-(vault_balance+(get_burned_supply() as u128)))

    }


    #[view]
    public fun full_coin_data(): CoinData acquires SupplyVault, CreationTime {

       let features =  Features {
            inflation: get_inflation() - (get_inflation_debt()*get_month()),
            base_inflation: get_inflation(),
            inflation_debt: get_inflation_debt(),
            creation_time: get_creation_time(),
            month: get_month(),
            burn_fee: (get_burn_fee_increase() * get_month()) + get_burn_fee(),
            base_burn_fee: get_burn_fee(),
            burn_fee_increase: get_burn_fee_increase(),
            treasury_fee: get_treasury_fee(),
            treasury_receipent: get_treasury_receipent(),
            transferable: is_transferable(),
        };

        let supply = Supply {
            innitial_supply: (INIT_SUPPLY as u128),
            circulating_supply: circulating_supply(),
            burned_supply: (U64_MAX as u128)-(circulating_supply()+(get_vault_balance() as u128)),
            innitial_vault_supply: (U64_MAX as u128)-(INIT_SUPPLY as u128),
            vault_supply: (get_vault_balance() as u128),
            claimable: claimable(),
        };

        CoinData{
            supply: supply,
            features: features,
            metadata: get_coin_metadata(),
        }

    }


}
