// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGroth16Verifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external view returns (bool);
}

contract PrivateDataStorage {
    IGroth16Verifier public immutable verifier;
    
    uint256 public activeRoot;
    // Track nullifiers or epochs to prevent replay attacks
    mapping(uint256 => bool) public usedNullifiers; 
        
    event StateUpdated(address indexed sender, uint256 newRoot, uint256 epoch);

    constructor(address _verifierAddress) {
        require(_verifierAddress != address(0), "Invalid verifier address");
        verifier = IGroth16Verifier(_verifierAddress);
    }

    function updateDataWithProof(uint[2] calldata _pA,uint[2][2] calldata _pB,uint[2] calldata _pC,uint[4] calldata _pubSignals) public {
        // 1. Verify the ZK Proof
        require(verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid ZK Proof");
        
        uint256 root = _pubSignals[1];
        uint256 epoch = _pubSignals[3];

        // 2. Prevent Replay Attacks, using epoch as nullifier in this case is enough
        // - Validators are being exchanged only at the start of each epoch.
        require(!usedNullifiers[epoch], "Proof already submitted (nullifier used)");
        require(activeRoot != root, "This root is already active");

        // 3. State Update
        activeRoot = root;
        usedNullifiers[epoch] = true;
        
        emit StateUpdated(msg.sender, root, epoch);
    }
}