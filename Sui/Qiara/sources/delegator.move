module 0x0::QiaraDelegatorV1 {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::groth16;
    use std::bcs;
    use sui::table::{Self, Table};
    use std::string::{String};
    use std::vector;
    use 0x0::QiaraMultiAssetVaultV1::{Self, AdminCap, Vault}; // this is the vault module
    use 0x0::QiaraExtractorV1::{Self as extractor};
    // Your VK here (keep as is for now)
    const FULL_VK: vector<u8> = x"e2f26dbea299f5223b646cb1fb33eadb059d9407559d7441dfd902e3a79a4d2dabb73dc17fbc13021e2471e0c08bd67d8401f52b73d6d07483794cad4778180e0c06f33bbc4c79a9cadef253a68084d382f17788f885c9afd176f7cb2f036789edf692d95cbdde46ddda5ef7d422436779445c5e66006a42761e1f12efde0018c212f3aeb785e49712e7a9353349aaf1255dfb31b7bf60723a480d9293938e1994104443cceed95af052872c157b48f9d628a58e1667d2975b6ea5f55a02ef196c70b1444a02c610e80735c26eb85ff36cfef258a65e8f265644a1809cff6f850f000000000000007bf13c3a8822c871dd9f1520465b97f508b34629ceba127b4406145da3ffcb2ebde442946eabfbe91818c321ff80288ef8e2dfa9cf0362a7a68c74b49facc40cbc18eb1a0f87ed60c222cfdc0e97cb7b8f61447c40b2fc58b6427851d888b5a8de6516d12f9a36165e93fc156a3418bb0c8f198510d25b07f686e1ad5d99fa17566296b7e8ef3d2f003e3757a444bb39bd96f5bd91ae0bf1eb58facd09c8468ae9f1fd35b79f3f79ae6f89b917ab5f973d262cb7dfd9fc48f0df275092684002c855fdc3e09ef5adcfde47633f889f576821ed36e55daa973a46a5a87e75000bea72a254220de1fd0de3efd64ad28b3700c939a47c0836a81cb3b3d72dd1d481fe0d9a9fc9d6c11609b94fa64f6b86d1ae1044def9711fbc5c51a7c1128a760dc7c0d800c903bc1e539bab7be24480fa4643e1cdb73b22883fa7fd46e59c2005a385a89c2dd6db5b2135a91063bfc458bb8a4f831193ca7021eae96f89ca6c25ab00f4aa06ff908b9ddc1d518fa6007c0237f26506dcbba6b78b420d9dd1eb8646bd9b28365078579e468f0a219e71d7c68b54f3bae5c22a12c872d996835b156a2aa0c0d3b716eb9b9dfc867a2cb345849f9b2278bb65904aad09e5fb4f3188fbb7f4bd90010edb0f6e161efaf9df6b938f7b0c624ec2515501e94d41db0f2a";
    
    const EInvalidProof: u64 = 0;
    const EInvalidPublicInputs: u64 = 1;
    const ENullifierUsed: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EWrongVaultProvided: u64 = 4;



    public struct Nullifiers has key, store {
        id: UID,
        table: table::Table<vector<u8>, bool>,
    }

    public struct ZkManager has key {
        id: UID,
        // The AdminCap will eventually live here as a Dynamic Field 
        // OR we can just send it to this Object's ID
    }

    fun init(ctx: &mut TxContext) {
        let nullifiers = Nullifiers { id: object::new(ctx),table: table::new(ctx) };
        transfer::share_object(nullifiers);

        let manager = ZkManager { id: object::new(ctx) };
        transfer::share_object(manager);
    }


    public entry fun verifyZK<T>(vault: &mut Vault, admin: &AdminCap, nullifiers: &mut Nullifiers, public_inputs: vector<u8>,proof_points: vector<u8>) {
        let curve = groth16::bn254();
        // 1. Sanity Check
        assert!(vector::length(&FULL_VK) > 0, 100);

        let pvk = groth16::prepare_verifying_key(&curve, &FULL_VK);

        // 2. Verify the proof
        let public_inputs_struct = groth16::public_proof_inputs_from_bytes(public_inputs);
        let proof_points_struct = groth16::proof_points_from_bytes(proof_points);

        assert!(groth16::verify_groth16_proof(&curve, &pvk, &public_inputs_struct, &proof_points_struct),EInvalidProof);

        // 3. Nullification Logic - Avoiding re-use
        let nullifier = extractor::extract_nullifier(&public_inputs);

        if(table::contains(&nullifiers.table, nullifier)) {
            abort ENullifierUsed;
        };  
        table::add(&mut nullifiers.table, nullifier, true);

        // TODO
        let user = extractor::extract_user_address(&public_inputs);
        let amount = extractor::extract_amount(&public_inputs);
        let vault_address_from_proof: address = extractor::extract_vault_address(&public_inputs);

        assert!(object::id_to_address(&object::id(vault)) == vault_address_from_proof, EWrongVaultProvided);
        //assert!(admin.vault_id == object::id(&vault), ENotAuthorized);

        // 4. Grant withdrawal permission
        //public entry fun grant_withdrawal_permission<T>(admin: &AdminCap, vault: &mut Vault, user: address, amount: u64)
        QiaraMultiAssetVaultV1::grant_withdrawal_permission<T>(admin, vault, user, amount)
    }
}