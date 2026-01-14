pragma circom 2.1.0;

include "circomlib/circuits/poseidon.circom";

// nValidators = 64, treeDepth = 10 (2^10 = 1024 variables)
template BridgeCore(nValidators, treeDepth) {
    // =====================
    // PUBLIC INPUTS
    // =====================
    signal input validatorRoot;  
    signal input epoch;          
    signal input variableID;     
    signal input newValue;       // Value being proposed

    // =====================
    // PRIVATE INPUTS
    // =====================
    signal input poseidonRoot;   
    signal input currentValue;  // <-- FIX: actual stored value
    signal input validatorPubKeys[nValidators]; 
    signal input sigSummary;     
    signal input pathElements[treeDepth]; 
    signal input pathIndices[treeDepth];

    // =====================================================
    // 1. VALIDATOR SET INTEGRITY
    // =====================================================
    component valHasher[63];
    signal valTree[127]; 

    for (var i = 0; i < nValidators; i++) {
        valTree[i] <== validatorPubKeys[i];
    }

    for (var i = 0; i < 63; i++) {
        valHasher[i] = Poseidon(2);
        valHasher[i].inputs[0] <== valTree[2*i];
        valHasher[i].inputs[1] <== valTree[2*i + 1];
        valTree[64 + i] <== valHasher[i].out;
    }

    // Must match on-chain validator root
    validatorRoot === valTree[126];


    // =====================================================
    // 2. STATE INCLUSION PROOF  (FIXED)
    // =====================================================
    component stateHasher[treeDepth];
    signal hashes[treeDepth + 1];

    // Leaf = Poseidon(variableID, currentValue)
    component leafHasher = Poseidon(2);
    leafHasher.inputs[0] <== variableID;
    leafHasher.inputs[1] <== currentValue;
    hashes[0] <== leafHasher.out;

    for (var i = 0; i < treeDepth; i++) {
        stateHasher[i] = Poseidon(2);

        // Standard indexed Merkle path logic
        stateHasher[i].inputs[0] <== hashes[i] 
            + pathIndices[i] * (pathElements[i] - hashes[i]);

        stateHasher[i].inputs[1] <== pathElements[i] 
            + pathIndices[i] * (hashes[i] - pathElements[i]);

        hashes[i+1] <== stateHasher[i].out;
    }

    // Must match the signed state root
    poseidonRoot === hashes[treeDepth];


    // =====================================================
    // 3. CRYPTOGRAPHIC BINDING
    // =====================================================
    component bindingHasher = Poseidon(4);
    bindingHasher.inputs[0] <== sigSummary;
    bindingHasher.inputs[1] <== epoch;
    bindingHasher.inputs[2] <== poseidonRoot;
    bindingHasher.inputs[3] <== newValue;   // <-- binds proposal value

    signal binding <== bindingHasher.out;

    // binding is what your Aptos event should emit
}

component main {public [validatorRoot, epoch, variableID, newValue]} 
    = BridgeCore(64, 10);
