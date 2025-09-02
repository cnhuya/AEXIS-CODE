module dev::QiaraGovernanceV10 {
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;
    use std::table::{Self, Table}; // left as-is; unused but kept if you plan to use it
    use supra_framework::event;
    use aptos_std::type_info;
    use aptos_std::timestamp;
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use supra_framework::object::{Self, Object};
    use supra_framework::primary_fungible_store;

    use dev::QiaraStorageV10::{Self as storage, Access};

    const OWNER: address = @dev;
    const QIARA_TOKEN: address = @0xf285a591bf76703f42e6e4aa7ed4d5b81a95bedeb0397afaca87084f52831bf8;
    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_CONSTANT_ALREADY_EXISTS: u64 = 2;
    const ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE: u64 = 3;
    const ERROR_PROPOSAL_NOT_FINISHED_YET: u64 = 4;

    // ----------------------------------------------------------------
    // Proposal count
    // ----------------------------------------------------------------

    struct ProposalCount has store, key, copy {
        count: u64
    }

    // ----------------------------------------------------------------
    // Storage Editing Capability 
    // ----------------------------------------------------------------

    struct StorageAccess has key, store {
        access: Access
    }

    // ----------------------------------------------------------------
    // Proposal resource
    // ----------------------------------------------------------------
    struct Proposal has store, drop, copy {
        id: u64,
        proposer: address,
        duration: u64,
        header: String,
        constant: String,
        new_value: vector<u8>,
        isChange: bool,
        editable: u8,
        yes: u64,
        no: u64,
        result: u8,
    }

    #[event]
    struct ProposeEvent has store, drop {
        id: u64,
        proposer: address,
        duration: u64,
        header: String,
        constant: String,
        isChange: bool,
        editable: u8,
        new_value: vector<u8>,
    }

    #[event]
    struct ProposalResultEvent has store, drop {
        id: u64,
        proposer: address,
        duration: u64,
        header: String,
        constant: String,
        new_value: vector<u8>,
        isChange: bool,
        editable: u8,
        yes: u64,
        no: u64,
        result: u8,
    }

    // ----------------------------------------------------------------
    // Proposal registry
    // ----------------------------------------------------------------
    struct PendingProposals has key {
        proposals: vector<Proposal>
    }

    fun make_proposal(id: u64,proposer: address,duration: u64,header: String,constant: String,isChange: bool,editable: u8,new_value: vector<u8>): Proposal {
        Proposal {id,proposer,duration,header,constant,new_value,isChange,editable,yes: 0,no: 0,result: 0}
    }

    fun get_qiara_balance(addr: address): u64 {
       fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(addr, object::address_to_object<Metadata>(QIARA_TOKEN)))
    }

    // ----------------------------------------------------------------
    // Initialize registry
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        if (!exists<PendingProposals>(OWNER)) {
            move_to(admin, PendingProposals { proposals: vector::empty<Proposal>()});
        };

        if (!exists<ProposalCount>(OWNER)) {
            move_to(admin, ProposalCount { count: 0});
        };

        if (!exists<StorageAccess>(OWNER)) {
            move_to(admin, StorageAccess { access: storage::give_access(admin)});
        };
        


    }

    // ----------------------------------------------------------------
    // Submit a proposal
    // ----------------------------------------------------------------
    public entry fun propose(proposer: &signer, isChange: bool, header: String, constant_name: String, new_value: vector<u8>, duration: u64, editable: u8) acquires PendingProposals, ProposalCount {
        let addr = signer::address_of(proposer);

        assert!(addr == OWNER, ERROR_NOT_ADMIN);
        assert!(get_qiara_balance(addr) >= storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"))), ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE);

        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let count_ref = borrow_global_mut<ProposalCount>(OWNER);

        // Use current counter value as the proposal id
        let proposal_id = count_ref.count;

        if(isChange == true){
            editable = 0;
        };

        // Create proposal
        let proposal = make_proposal(proposal_id, addr, duration, header, constant_name, isChange,editable, new_value);

        vector::push_back(&mut registry.proposals, proposal);

        // Emit event
        event::emit(ProposeEvent {
            id: proposal_id,
            proposer: addr,
            duration,
            header,
            constant: constant_name,
            isChange,
            editable,
            new_value,
        });

        // increment stored count
        count_ref.count = count_ref.count + 1;
    }

    // ----------------------------------------------------------------
    // Finalize a proposal
    // ----------------------------------------------------------------
    public entry fun finalize_proposal(user: &signer, proposal_id: u64) acquires PendingProposals, StorageAccess {
        let addr = signer::address_of(user);

        assert!(addr == OWNER, ERROR_NOT_ADMIN);
        assert!(get_qiara_balance(addr) >= 100000, ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE);

        let registry = borrow_global_mut<PendingProposals>(OWNER);

        let len = vector::length(&registry.proposals);

        // iterate backwards to allow safe removal while iterating
        while (len > 0) {
            let idx = len - 1;
            let proposal_ref = vector::borrow(&registry.proposals, idx);

            if (proposal_ref.id == proposal_id) {
                assert!(timestamp::now_seconds() > proposal_ref.duration, ERROR_PROPOSAL_NOT_FINISHED_YET);

                // copy the proposal out so we can emit event after removing it
                let proposal_copy = *proposal_ref; // Proposal is 'copy' so this is allowed


                if(proposal_copy.isChange == true){
                    storage::change_constant(user, proposal_copy.header, proposal_copy.constant, proposal_copy.new_value, &storage::give_change_permission(&borrow_global<StorageAccess>(OWNER).access));
                } else {
                    storage::change_constant(user, proposal_copy.header, proposal_copy.constant, proposal_copy.new_value, &storage::give_change_permission(&borrow_global<StorageAccess>(OWNER).access));
                };

                vector::remove(&mut registry.proposals, idx);
                let result: u8;
                if (proposal_copy.yes >= proposal_copy.no){
                    result = 1;
                } else {
                    result = 2;
                };
                // emit result event using the removed proposal's fields
                event::emit(ProposalResultEvent {
                    id: proposal_copy.id,
                    proposer: proposal_copy.proposer,
                    duration: proposal_copy.duration,
                    header: proposal_copy.header,
                    constant: proposal_copy.constant,
                    isChange: proposal_copy.isChange,
                    editable: proposal_copy.editable,
                    new_value: proposal_copy.new_value,
                    yes: proposal_copy.yes,
                    no: proposal_copy.no,
                    result: result,
                });

                // finished: break out after handling the target proposal
                break;
            };

            // move to the previous element
            len = len - 1;
        }
    }
}
