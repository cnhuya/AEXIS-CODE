// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[6] calldata _pubSignals) external view returns (bool);
}

// Interface for your Vaults
interface IQiaraVault {
    function grantWithdrawalPermission(address user, uint256 amount) external;
}

contract QiaraZKDelegator {
    IVerifier public immutable verifier;
    
    // mapping(tokenAddress => vaultAddress)
    mapping(address => address) public tokenToVault;

    constructor(address _verifier) {
        verifier = IVerifier(_verifier);
    }

    // Admin adds a new token/vault pair to the system
    function listNewToken(address token, address vault) external {
        // Add owner check here
        tokenToVault[token] = vault;
    }

    function processZkWithdraw(
        uint[2] calldata _pA, 
        uint[2][2] calldata _pB, 
        uint[2] calldata _pC, 
        uint[6] calldata _pubSignals
    ) external {
        // 1. Verify Proof
        require(verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        // 2. Extract Signals from your Circom Circuit
        // signal output outUserAddress; -> index 3
        // signal output outStorageID;   -> index 4 (The Token Address)
        // signal output amount;         -> index 5 (Whatever signal represents withdrawal amount)
        address user = address(uint160(_pubSignals[3]));
        address token = address(uint160(_pubSignals[4]));
        uint256 amount = _pubSignals[5];

        // 3. Find the Vault for this token
        address vault = tokenToVault[token];
        require(vault != address(0), "Token not supported");

        // 4. Cross-Contract Call: Grant the permission
        IQiaraVault(vault).grantWithdrawalPermission(user, amount);
    }
}