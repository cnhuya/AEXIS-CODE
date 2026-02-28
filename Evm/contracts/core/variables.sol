// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals) external view returns (bool);
}

//0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000058307832613330373833303434333533333332333234313636333433313334363436323333363236343338333533353633343333343334333433323334343633383335333333323338333533393334333633393339333533370000000000000000

contract QiaraVariables {
    error RegistryLocked();
    error NotAuthorized();
    error InvalidProof();
    error RootAlreadyExists();
    error InputMismatch();
    error AdminBypassRevoked(); // New Error

    address public admin;
    bool public isLocked;
    bool public adminBypassEnabled = true; // New State variable
    IVerifier public verifier;
    uint256 public currentRoot;

    mapping(string => mapping(string => bytes)) private _data;

    event VariableAdded(string indexed header, string indexed name, address by, uint256 newRoot);
    event AdminBypassPermanentlyDisabled(); // New Event

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAuthorized();
        _;
    }

    constructor(address _verifier) {
        admin = msg.sender;
        verifier = IVerifier(_verifier);
    }

    /**
     * @dev PERMANENTLY revokes the admin's ability to skip ZK proofs.
     * This action cannot be undone.
     */
    function revokeAdminBypass() external onlyAdmin {
        adminBypassEnabled = false;
        emit AdminBypassPermanentlyDisabled();
    }

    /**
     * @dev ADMIN ONLY: Adds variable without ZK proof IF bypass is still enabled.
     */
    function adminAddVariable(string calldata header, string calldata name, bytes calldata data) external onlyAdmin {
        if (!adminBypassEnabled) revert AdminBypassRevoked();
        if (isLocked) revert RegistryLocked();

        _save(header, name, data);
    }
    function adminSetRoot(uint256 newRoot) external onlyAdmin {
        if (!adminBypassEnabled) revert AdminBypassRevoked();
        if (isLocked) revert RegistryLocked();
        if (newRoot == currentRoot) revert RootAlreadyExists();
        currentRoot = newRoot;
    }

    /**
     * @dev PUBLIC: Add variable WITH a ZK proof. 
     * This remains the only way to add data once admin bypass is revoked.
     */
    function AddVariable(string calldata header, string calldata name, bytes calldata data,uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals) external {
        if (isLocked) revert RegistryLocked();

        // Safecheck Root (pubSignals[1])
        uint256 newRoot = _pubSignals[1];
        if (newRoot == currentRoot) revert RootAlreadyExists();

        // Verify ZK Proof
        if(!verifier.verifyProof(_pA, _pB, _pC, _pubSignals)) revert InvalidProof();

        currentRoot = newRoot;
        _save(header, name, data);
    }

    function _save(string calldata header, string calldata name, bytes calldata data) internal {
        _data[header][name] = data;
        emit VariableAdded(header, name, msg.sender, currentRoot);
    }

    function getVariable(string calldata header, string calldata name) external view returns (bytes memory) {
        return _data[header][name];
    }
}