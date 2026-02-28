// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IVerifier {
    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[8] calldata _pubSignals) external view returns (bool);
}

interface IQiaraVault {
    function grantWithdrawalPermission(address user, string memory assetName, uint256 amount, uint256 nullifier) external;
}

interface IVariables {
   function getVariable(string calldata header, string calldata name) external view returns (bytes memory);
}

contract QiaraZKDelegator is Ownable {
    IVerifier public immutable verifier;
    IVariables public immutable variablesRegistry;
    
    // Mapping to prevent replay attacks
    mapping(uint256 => bool) public usedNullifiers;

    constructor(address _verifier, address _variablesRegistry) Ownable(msg.sender) {
        verifier = IVerifier(_verifier);
        variablesRegistry = IVariables(_variablesRegistry);
    }

    function processZkWithdraw(
        uint[2] calldata _pA, 
        uint[2][2] calldata _pB, 
        uint[2] calldata _pC, 
        uint[8] calldata _pubSignals
    ) external {
        // 1. Verify ZK Proof
        require(verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");

        // 2. Unpacked Slot 8 (packedTxData)
        uint256 packed = _pubSignals[7];
        uint256 chainID = packed & 0xFFFFFFFF;
        uint256 amount = (packed >> 32) & 0xFFFFFFFFFFFFFFFF;
        uint256 nonce = (packed >> 96);

        require(chainID == block.chainid, "Wrong destination chain");

        // 3. Convert Field Values to Strings
        string memory storageName = fieldToString(_pubSignals[5]);
        string memory providerName = fieldToString(_pubSignals[6]);

        // 4. Dynamic Registry Lookup
        string memory vaultKey = string(abi.encodePacked(providerName, "_vault"));
        bytes memory vaultBytes = variablesRegistry.getVariable("QiaraBaseAssets", vaultKey);
        require(vaultBytes.length > 0, "Vault not authorized in registry");
        
        address vaultAddr = abi.decode(vaultBytes, (address));

        // 5. Replay Protection (Using SHA256)
        uint256 userL = _pubSignals[3];
        uint256 userH = _pubSignals[4];
        uint256 nullifier = _calculateSHA256Nullifier(userL, userH, nonce);
        
        require(!usedNullifiers[nullifier], "Replay attack detected");
        usedNullifiers[nullifier] = true;

        // 6. User Address Reconstruction
        address user = address(uint160((userH << 128) | userL));

        // 7. Final Call
        IQiaraVault(vaultAddr).grantWithdrawalPermission(user, storageName, amount, nullifier);
    }

    /**
     * @dev Replaces Poseidon with SHA256. 
     * We pack the three uint256 values and hash them.
     */
    function _calculateSHA256Nullifier(uint256 userL, uint256 userH, uint256 nonce) internal pure returns (uint256) {
        // Reconstruct full 32-byte address padding (12 bytes 0 + 20 bytes address)
        // or simply pack the raw field elements as they come from the circuit:
        bytes32 userBytes = bytes32((userH << 128) | userL);
        
        // Hash: [32 bytes address] + [32 bytes nonce] = 64 bytes input
        return uint256(sha256(abi.encodePacked(userBytes, nonce)));
    }

    function fieldToString(uint256 _field) public pure returns (string memory) {
        if (_field == 0) return "";

        // Step 1: Cast to bytes32 to access individual bytes
        bytes32 b32 = bytes32(_field);
        
        // Step 2: Find the first non-zero byte (start of the string)
        uint8 start = 0;
        while (start < 32 && b32[start] == 0) {
            start++;
        }

        // Step 3: Find the last non-zero byte (end of the string)
        // This handles cases where there might be trailing zeros
        uint8 end = 31;
        while (end > start && b32[end] == 0) {
            end--;
        }

        uint8 len = (end - start) + 1;
        bytes memory result = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            result[i] = b32[start + i];
        }

        return string(result);
    }
}