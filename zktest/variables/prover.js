const snarkjs = require("snarkjs");
const { buildPoseidon } = require("circomlibjs");
const inputJson = require("../input.json");

// Must match circuit
const LEVELS = 10;

async function buildPoseidonMerkle(leaves) {
    const poseidon = await buildPoseidon();

    // hash leaves if they aren't already field elements
    let nodes = leaves.map(v => poseidon([BigInt(v)]));

    // build tree
    const tree = [nodes];
    for (let i = 0; i < LEVELS; i++) {
        const layer = tree[i];
        const next = [];
        for (let j = 0; j < layer.length; j += 2) {
            const left = layer[j];
            const right = layer[j + 1] ?? poseidon([0n]); // pad with zero leaf
            next.push(poseidon([left, right]));
        }
        tree.push(next);
    }
    return { tree, poseidon };
}

function getProof(tree, poseidon, index) {
    let siblings = [];
    let indices = [];
    let idx = index;

    for (let level = 0; level < LEVELS; level++) {
        const layer = tree[level];
        const isRight = idx % 2;
        const pairIndex = isRight ? idx - 1 : idx + 1;

        const sibling = layer[pairIndex] ?? poseidon([0n]);
        siblings.push(sibling);
        indices.push(isRight);

        idx = Math.floor(idx / 2);
    }

    return { siblings, indices };
}

async function prepareBatch() {
    // Use the variableID and newValue from input.json
    const call = {
        variableID: inputJson.variableID,
        newValue: inputJson.newValue
    };

    // Convert to numeric leaf
    const leafValue = BigInt("0x" + Buffer.from(JSON.stringify(call)).toString("hex"));
    
    // Build tree with a single leaf
    const { tree, poseidon } = await buildPoseidonMerkle([leafValue]);
    
    const root = tree[LEVELS][0];
    const proof = getProof(tree, poseidon, 0);

    // Build snarkjs input
const input = {
        validatorRoot: BigInt(inputJson.validatorRoot),
        epoch: BigInt(inputJson.epoch),
        variableID: BigInt(inputJson.variableID),
        newValue: BigInt(inputJson.newValue),
        poseidonRoot: BigInt(inputJson.poseidonRoot),
        currentValue: BigInt(inputJson.currentValue), // Add this line
        validatorPubKeys: inputJson.validatorPubKeys.map(pk => BigInt(pk)),
        sigSummary: BigInt(inputJson.sigSummary),
        pathElements: inputJson.pathElements.map(e => BigInt(e)),
        pathIndices: inputJson.pathIndices
    };


    // Generate Groth16 proof
    const { proof: zkProof, publicSignals } = await snarkjs.groth16.fullProve(
        input,
        "./zk/circuit.wasm",
        "./zk/circuit_final.zkey"
    );

    // Format proof for chain / CLI
    const pA = zkProof.pi_a.slice(0, 2);
    const pB = [zkProof.pi_b[0].reverse(), zkProof.pi_b[1].reverse()];
    const pC = zkProof.pi_c.slice(0, 2);

    console.log("\n--- Proof ready ---");
    console.log("Public signals:", publicSignals);
    console.log("pA:", pA);
    console.log("pB:", pB);
    console.log("pC:", pC);

    return { pA, pB, pC, publicSignals };
}

module.exports = { prepareBatch };
