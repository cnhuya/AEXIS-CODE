const snarkjs = require("snarkjs");
const inputJson = require("../input.json");

async function prepareBatch() {
    // 1. Map the new complex input structure to BigInts for snarkjs
    const input = {
        currentValidatorRoot: BigInt(inputJson.currentValidatorRoot),
        newValidatorRoot: BigInt(inputJson.newValidatorRoot),
        epoch: BigInt(inputJson.epoch),
        
        // Validator Data Arrays
        validatorPubKeysX: inputJson.validatorPubKeysX.map(x => BigInt(x)),
        validatorPubKeysY: inputJson.validatorPubKeysY.map(y => BigInt(y)),
        validatorStakes: inputJson.validatorStakes.map(s => BigInt(s)),
        isSigned: inputJson.isSigned.map(i => BigInt(i)),

        // Signature Arrays
        signaturesR8x: inputJson.signaturesR8x.map(x => BigInt(x)),
        signaturesR8y: inputJson.signaturesR8y.map(y => BigInt(y)),
        signaturesS: inputJson.signaturesS.map(s => BigInt(s)),

        // Inclusion Proofs (2D Arrays)
        valPathElements: inputJson.valPathElements.map(row => 
            row.map(element => BigInt(element))
        ),
        valPathIndices: inputJson.valPathIndices.map(row => 
            row.map(index => BigInt(index))
        )
    };

    console.log("Generating proof for epoch:", input.epoch.toString());

    // 2. Generate Groth16 proof
    const { proof: zkProof, publicSignals } = await snarkjs.groth16.fullProve(
        input,
        "./zk/validators/circuit.wasm",
        "./zk/validators/circuit_final.zkey"
    );

    // 3. Format proof for CLI/Chain
    // pA and pC are G1 points [X, Y]
    const pA = zkProof.pi_a.slice(0, 2);
    const pC = zkProof.pi_c.slice(0, 2);

    // pB is a G2 point. 
    // Requirement: Concatenate as [X Real, X Imaginary, Y Real, Y Imaginary]
    // snarkjs gives pi_b as [[real, imag], [real, imag], [1]]
const pB = [
    zkProof.pi_b[0][0], // Keep SnarkJS order (usually Imaginary)
    zkProof.pi_b[0][1], // Keep SnarkJS order (usually Real)
    zkProof.pi_b[1][0], 
    zkProof.pi_b[1][1]
];

    console.log("\n--- Proof ready ---");
    console.log("Public signals (Total Signed Stake):", publicSignals);
    console.log("pA:", pA);
    console.log("pB:", pB);
    console.log("pC:", pC);

    return { pA, pB, pC, publicSignals };
}

module.exports = { prepareBatch };