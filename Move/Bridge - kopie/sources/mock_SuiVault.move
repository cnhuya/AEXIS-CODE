module dev::vaults {
    use std::table;
    use std::signer;
    use std::type_info;
    use supra_framework::coin;

    /// Per-user, per-coin accounting (simple scalars).
    /// NOTE: Values in a Table must have `store`. They do NOT need `key`.
    struct UserVault has store, copy, drop {
        deposited: u64,
        borrowed: u64,
        rewards: u64,
        interest: u64,
        last_update: u64,
    }

    /// A user's handle holding many coin positions by type.
    struct UserVaultHandle has key {
        vaults: table::Table<type_info::TypeInfo, UserVault>,
    }

    /// Global per-coin vault lives as its own resource. Holds actual Coin<T>.
    struct GlobalVault<phantom T> has key {
        total_deposited: u64,
        balance: coin::Coin<T>,
    }

    /// One handle that can reference many GlobalVault<T> via address indirection.
    struct VaultHandle has key {
        // maps coin type -> address where GlobalVault<T> is stored
        vaults: table::Table<type_info::TypeInfo, address>,
    }

    /* -------------------- init helpers -------------------- */

    public fun init_user_handle(user: &signer) {
        move_to(user, UserVaultHandle { vaults: table::new() });
    }

    public fun init_vault_handle(admin: &signer) {
        move_to(admin, VaultHandle { vaults: table::new() });
    }

    /* ---------------- ensure/create per-coin resources ---------------- */

    /// Ensure there is a GlobalVault<T> resource and it is registered in the handle.
    /// We store the GlobalVault<T> under `admin_addr` (the module's signer here).
    public fun ensure_global_vault<T>(admin: &signer, vh: &mut VaultHandle) {
        let ti = type_info::type_of<T>();
        if (!table::contains(&vh.vaults, ti)) {
            // create the per-coin resource
            let gv = GlobalVault<T> { total_deposited: 0, balance: coin::zero<T>() };
            move_to(admin, gv);
            table::add(&mut vh.vaults, ti, signer::address_of(admin));
        }
    }

    /// Ensure a per-coin UserVault row exists for this user.
    public fun ensure_user_vault<T>(uvh: &mut UserVaultHandle, now: u64) {
        let ti = type_info::type_of<T>();
        if (!table::contains(&uvh.vaults, ti)) {
            table::add(
                &mut uvh.vaults,
                ti,
                UserVault { deposited: 0, borrowed: 0, rewards: 0, interest: 0, last_update: now }
            );
        }
    }

    /* ----------------------- core ops ----------------------- */

   // public entry fun depositReal(signer, coin{


    /// Deposit coins into the global vault and update user's per-coin accounting.
    /// `admin` is where GlobalVault<T> lives; `user` supplies the coins.
    public fun deposit<T>(
        admin: &signer,
        vh: &mut VaultHandle,
        uvh: &mut UserVaultHandle,
        coins: coin::Coin<T>,
        now: u64,
    ) acquires GlobalVault{
        // make sure the per-coin global vault exists & is registered
        ensure_global_vault<T>(admin, vh);

        // find where the GlobalVault<T> lives
        let ti = type_info::type_of<T>();
        let addr_ref = table::borrow(&vh.vaults, ti);
        let gv = borrow_global_mut<GlobalVault<T>>(*addr_ref);

        // update global vault
        let amt = coin::value(&coins);
        gv.total_deposited = gv.total_deposited + amt;
        coin::merge(&mut gv.balance, coins);

        // update user vault row (scalar fields)
        ensure_user_vault<T>(uvh, now);
        let uv_ref = table::borrow_mut(&mut uvh.vaults, ti);
        uv_ref.deposited = uv_ref.deposited + amt;
        uv_ref.last_update = now;
    }

    /// Withdraw up to the user's deposited amount (no borrow logic here).
    public fun withdraw<T>(
        signer: &signer,
        vh: &VaultHandle,
        uvh: &mut UserVaultHandle,
        amount: u64,
        recipient: address,
        now: u64,
    ) acquires GlobalVault {
        let ti = type_info::type_of<T>();

        // check user balance
        let uv_ref = table::borrow_mut(&mut uvh.vaults, ti);
        assert!(uv_ref.deposited >= amount, 1); // E_INSUFFICIENT_USER_DEPOSIT
        uv_ref.deposited = uv_ref.deposited - amount;
        uv_ref.last_update = now;

        // global vault
        let addr_ref = table::borrow(&vh.vaults,ti);
        let gv = borrow_global_mut<GlobalVault<T>>(*addr_ref);
        assert!(gv.total_deposited >= amount, 2); // E_INSUFFICIENT_GLOBAL_LIQUIDITY

        // split from the pooled coin balance

        let coins = coin::extract(&mut gv.balance, amount);
        coin::deposit(signer::address_of(signer), coins);
        gv.total_deposited = gv.total_deposited - amount;

        // optionally transfer to recipient; here we just return the coin
        // (callers can `coin::transfer<T>(out, recipient)` if desired)
    }

    /* ---------------------- view helpers ---------------------- */

    public fun get_user_vault<T>(uvh: &UserVaultHandle): UserVault {
        let ti = type_info::type_of<T>();
        *table::borrow(&uvh.vaults, ti)
    }

    public fun get_global_totals<T>(vh: &VaultHandle, admin_addr: address): (u64, u64) acquires GlobalVault {
        let ti = type_info::type_of<T>();
        let addr_ref = table::borrow(&vh.vaults, ti);
        let gv = borrow_global<GlobalVault<T>>(*addr_ref);
        (gv.total_deposited, coin::value(&gv.balance))
    }
}
