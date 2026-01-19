pragma circom 2.1.0;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/eddsaposeidon.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/mux1.circom"; // Added for safe selection

template ValidatorRotationWithStake(nValidators, valTreeDepth, threshold) {
    
    // Public Inputs
    signal input currentValidatorRoot; 
    signal input newValidatorRoot;     
    signal input epoch;                
    
    // Validator Data
    signal input validatorPubKeysX[nValidators]; 
    signal input validatorPubKeysY[nValidators];
    signal input validatorStakes[nValidators]; 
    
    // Signatures
    
    signal input signaturesR8x[nValidators];
    signal input signaturesR8y[nValidators];
    signal input signaturesS[nValidators];
    signal input isSigned[nValidators]; 

    // Inclusion Proofs
    signal input valPathElements[nValidators][valTreeDepth]; 
    signal input valPathIndices[nValidators][valTreeDepth];

    // --- OUTPUTS ---
    signal output totalSignedStake;

    // 1. Message Commitment
    component msgHasher = Poseidon(3);
    msgHasher.inputs[0] <== currentValidatorRoot;
    msgHasher.inputs[1] <== newValidatorRoot;
    msgHasher.inputs[2] <== epoch;

    // 2. Declarations
    component leafHasher[nValidators];
    component valMembership[nValidators];
    component eddsa[nValidators];
    
    signal cumulativeStake[nValidators + 1];
    signal cumulativeSignatures[nValidators + 1];
    
    cumulativeStake[0] <== 0;
    cumulativeSignatures[0] <== 0;

    // 3. Verification Loop
    for (var i = 0; i < nValidators; i++) {
        leafHasher[i] = Poseidon(3); 
        leafHasher[i].inputs[0] <== validatorPubKeysX[i];
        leafHasher[i].inputs[1] <== validatorPubKeysY[i];
        leafHasher[i].inputs[2] <== validatorStakes[i];

        valMembership[i] = MerkleProof(valTreeDepth); 
        valMembership[i].leaf <== leafHasher[i].out;
        for (var j = 0; j < valTreeDepth; j++) {
            valMembership[i].pathElements[j] <== valPathElements[i][j];
            valMembership[i].pathIndices[j] <== valPathIndices[i][j];
        }
        valMembership[i].root === currentValidatorRoot;

        eddsa[i] = EdDSAPoseidonVerifier();
        eddsa[i].enabled <== isSigned[i];
        eddsa[i].Ax <== validatorPubKeysX[i];
        eddsa[i].Ay <== validatorPubKeysY[i];
        eddsa[i].R8x <== signaturesR8x[i];
        eddsa[i].R8y <== signaturesR8y[i];
        eddsa[i].S <== signaturesS[i];
        eddsa[i].M <== msgHasher.out;

        cumulativeSignatures[i+1] <== cumulativeSignatures[i] + isSigned[i];
        cumulativeStake[i+1] <== cumulativeStake[i] + (isSigned[i] * validatorStakes[i]);
    }

    totalSignedStake <== cumulativeStake[nValidators];

    // 4. Quorum Check
    component checkThreshold = GreaterEqThan(8); 
    checkThreshold.in[0] <== cumulativeSignatures[nValidators];
    checkThreshold.in[1] <== threshold;
    checkThreshold.out === 1;
}

// Fixed MerkleProof Template
template MerkleProof(depth) {
    signal input leaf;
    signal input pathElements[depth];
    signal input pathIndices[depth];
    signal output root;

    component hashes[depth];
    component selectors[depth][2];
    
    // We create an array of signals to hold the "running" hash value
    signal levelHashes[depth + 1];
    levelHashes[0] <== leaf;

    for (var i = 0; i < depth; i++) {
        hashes[i] = Poseidon(2);
        selectors[i][0] = Mux1();
        selectors[i][1] = Mux1();

        // If pathIndices[i] == 0: [prev, element]
        // If pathIndices[i] == 1: [element, prev]
        selectors[i][0].c[0] <== levelHashes[i];
        selectors[i][0].c[1] <== pathElements[i];
        selectors[i][0].s <== pathIndices[i];

        selectors[i][1].c[0] <== pathElements[i];
        selectors[i][1].c[1] <== levelHashes[i];
        selectors[i][1].s <== pathIndices[i];

        hashes[i].inputs[0] <== selectors[i][0].out;
        hashes[i].inputs[1] <== selectors[i][1].out;
        
        levelHashes[i+1] <== hashes[i].out;
    }

    root <== levelHashes[depth];
}

component main {public [currentValidatorRoot, newValidatorRoot, epoch]} = ValidatorRotationWithStake(8, 4, 2);