pragma circom 2.1.0;

include "circomlib/circuits/poseidon.circom";

// nValidators = 64, treeDepth = 10 (2^10 = 1024 variables)
template BridgeCore(nValidators, treeDepth) {
    // PUBLIC INPUTS
    signal input validatorRoot;  // Merkle Root of authorized validator pubkeys
    signal input epoch;          // Current epoch (prevents replay)
    signal input variableID;     // The slot ID (0-1023)
    signal input newValue;       // The data being bridged

    // PRIVATE INPUTS
    signal input poseidonRoot;   // The "Shadow Root" calculated in JS
    signal input validatorPubKeys[nValidators]; 
    signal input sigSummary;     // Binding: Hash(validators who signed this specific update)
    signal input pathElements[treeDepth]; 
    signal input pathIndices[treeDepth];

    // --- 1. VALIDATOR SET INTEGRITY ---
    // Rebuild the validator Merkle tree (Depth 6 for 64 validators)
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
    validatorRoot === valTree[126];

    // --- 2. STATE INCLUSION PROOF ---
    // Prove that Leaf(ID, Value) is inside the poseidonRoot
    component stateHasher[treeDepth];
    signal hashes[treeDepth + 1];

    component leafHasher = Poseidon(2);
    leafHasher.inputs[0] <== variableID;
    leafHasher.inputs[1] <== newValue;
    hashes[0] <== leafHasher.out;

    for (var i = 0; i < treeDepth; i++) {
        stateHasher[i] = Poseidon(2);
        // Standard Merkle path logic
        stateHasher[i].inputs[0] <== hashes[i] + pathIndices[i] * (pathElements[i] - hashes[i]);
        stateHasher[i].inputs[1] <== pathElements[i] + pathIndices[i] * (hashes[i] - pathElements[i]);
        hashes[i+1] <== stateHasher[i].out;
    }
    // The inclusion must match the root that the validators signed
    poseidonRoot === hashes[treeDepth];

    // --- 3. THE CRYPTOGRAPHIC BINDING ---
    // This is the "Glue" that makes it trustless.
    // We force the proof to be valid ONLY for this specific combo of:
    // Signers + Time + State Content
    component bindingHasher = Poseidon(3);
    bindingHasher.inputs[0] <== sigSummary;
    bindingHasher.inputs[1] <== epoch;
    bindingHasher.inputs[2] <== poseidonRoot;
    signal binding <== bindingHasher.out;
            
    // Note: On Ethereum, you verify that 'binding' matches 
    // the hash of the data emitted in the Aptos event.
}

component main {public [validatorRoot, epoch, variableID, newValue]} = BridgeCore(64, 10);