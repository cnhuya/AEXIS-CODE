module dev::QiaraGovernanceV13 {
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;
    use supra_framework::event;
    use aptos_std::type_info;
    use aptos_std::timestamp;
    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use supra_framework::object::{Self, Object};
    use supra_framework::primary_fungible_store;
    use aptos_std::from_bcs;

    use dev::QiaraStorageV13::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV13::{Self as capabilities, Access as CapabilitiesAccess};

    const OWNER: address = @dev;
    const QIARA_TOKEN: address = @0xf285a591bf76703f42e6e4aa7ed4d5b81a95bedeb0397afaca87084f52831bf8;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_CONSTANT_ALREADY_EXISTS: u64 = 2;
    const ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE: u64 = 3;
    const ERROR_PROPOSAL_NOT_FINISHED_YET: u64 = 4;
    const ERROR_INVALIED_PROPOSAL_TYPE: u64 = 5;

    struct ProposalCount has store, key, copy { count: u64 }

    struct Access has key, store, drop {
        storage_access: StorageAccess,
        capabilities_access: CapabilitiesAccess
    }


    struct Proposal has store, drop, copy {
        id: u64,
        type: String,
        proposer: address,
        duration: u64,
        header: String,
        constant: String,
        new_value: vector<u8>,
        isChange: bool,
        editable: bool,
        yes: u64,
        no: u64,
        result: u8,
    }

    #[event]
    struct ProposeEvent has store, drop {
        id: u64,
        type: String,
        proposer: address,
        duration: u64,
        header: String,
        constant: String,
        isChange: bool,
        editable: bool,
        new_value: vector<u8>,
    }

    #[event]
    struct ProposalResultEvent has store, drop {
        id: u64,
        type: String,
        proposer: address,
        duration: u64,
        header: String,
        constant: String,
        new_value: vector<u8>,
        isChange: bool,
        editable: bool,
        yes: u64,
        no: u64,
        result: u8,
    }

    struct PendingProposals has key {
        proposals: vector<Proposal>
    }

    fun make_proposal(id: u64, type: String, proposer: address, duration: u64, header: String, constant: String, isChange: bool, editable: bool, new_value: vector<u8>): Proposal {
        Proposal {id, type, proposer, duration, header, constant, new_value, isChange, editable, yes: 0, no: 0, result: 0}
    }

    fun get_qiara_balance(addr: address): u64 {
        fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(addr, object::address_to_object<Metadata>(QIARA_TOKEN)))
    }

    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<PendingProposals>(OWNER)) {
            move_to(admin, PendingProposals { proposals: vector::empty<Proposal>() });
        };

        if (!exists<ProposalCount>(OWNER)) {
            move_to(admin, ProposalCount { count: 0 });
        };

        if (!exists<Access>(OWNER)) {
            move_to(admin, Access {
                storage_access: storage::give_access(admin),
                capabilities_access: capabilities::give_access(admin)
            });
        };
    }

    public entry fun propose(proposer: &signer, type: String, isChange: bool, header: String, constant_name: String, new_value: vector<u8>, duration: u64, editable: bool) acquires PendingProposals, ProposalCount {
        let addr = signer::address_of(proposer);
        assert_allowed_type(type);
        assert!(addr == OWNER, ERROR_NOT_ADMIN);
        assert!(get_qiara_balance(addr) >= storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"))), ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE);

        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let count_ref = borrow_global_mut<ProposalCount>(OWNER);
        let proposal_id = count_ref.count;

        let proposal = make_proposal(proposal_id, type, addr, duration, header, constant_name, isChange, editable, new_value);
        vector::push_back(&mut registry.proposals, proposal);

        event::emit(ProposeEvent {
            id: proposal_id,
            type: type,
            proposer: addr,
            duration,
            header,
            constant: constant_name,
            isChange,
            editable,
            new_value,
        });

        count_ref.count = count_ref.count + 1;
    }

    public entry fun finalize_proposal(user: &signer, proposal_id: u64) acquires PendingProposals, Access {
        let addr = signer::address_of(user);
        assert!(addr == OWNER, ERROR_NOT_ADMIN);
        assert!(get_qiara_balance(addr) >= 100000, ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE);

        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let len = vector::length(&registry.proposals);

        while (len > 0) {
            let idx = len - 1;
            let proposal_ref = vector::borrow(&registry.proposals, idx);

            if (proposal_ref.id == proposal_id) {
                assert!(timestamp::now_seconds() > proposal_ref.duration, ERROR_PROPOSAL_NOT_FINISHED_YET);
                let proposal_copy = *proposal_ref;


                if(proposal_copy.type == utf8(b"Storage")){
                    if (proposal_copy.isChange) {
                        storage::change_constant(user, proposal_copy.header, proposal_copy.constant, proposal_copy.new_value, &storage::give_change_permission(&borrow_global<Access>(OWNER).storage_access));
                    } else {
                       storage::register_constant(user, proposal_copy.header, proposal_copy.constant, proposal_copy.new_value, proposal_copy.editable, &storage::give_change_permission(&borrow_global<Access>(OWNER).storage_access));
                    };
                } else if (proposal_copy.type==utf8(b"Capabilities")){
                    if (proposal_copy.isChange) {
                        capabilities::remove_capability(user, from_bcs::to_address(proposal_copy.new_value), proposal_copy.header, proposal_copy.constant, capabilities::give_change_permission(&borrow_global<Access>(OWNER).capabilities_access));
                    } else {
                        capabilities::create_capability(user, from_bcs::to_address(proposal_copy.new_value), proposal_copy.header, proposal_copy.constant, proposal_copy.editable, capabilities::give_change_permission(&borrow_global<Access>(OWNER).capabilities_access));
                    };
                };
                vector::remove(&mut registry.proposals, idx);
                let result: u8 = if (proposal_copy.yes >= proposal_copy.no) { 1 } else { 2 };

                event::emit(ProposalResultEvent {
                    id: proposal_copy.id,
                    type: type_info::type_name<Proposal>(),
                    proposer: proposal_copy.proposer,
                    duration: proposal_copy.duration,
                    header: proposal_copy.header,
                    constant: proposal_copy.constant,
                    new_value: proposal_copy.new_value,
                    isChange: proposal_copy.isChange,
                    editable: proposal_copy.editable,
                    yes: proposal_copy.yes,
                    no: proposal_copy.no,
                    result,
                });

                break;
            };

            len = len - 1;
        }
    }

    fun assert_allowed_type(type: String){
        assert!(type == utf8(b"Storage") || type == utf8(b"Capabilities"), ERROR_INVALIED_PROPOSAL_TYPE);
    }
}
