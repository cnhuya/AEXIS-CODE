const snarkjs = require("snarkjs");
const path = require("path");
const fs = require('fs').promises; 

function deepToBigInt(obj) {
    // 1. Handle non-objects (Strings, Numbers, Booleans)
    if (typeof obj !== 'object' || obj === null) {
        // Check if it's a string that looks like a number or hex
        if (typeof obj === 'string') {
            // Check for digits or hex (0x...)
            const isNumeric = /^-?\d+$/.test(obj) || /^0x[0-9a-fA-F]+$/.test(obj);
            return isNumeric ? BigInt(obj) : obj;
        }
        // If it's a number, convert to BigInt
        if (typeof obj === 'number') return BigInt(obj);
        
        return obj;
    }
    
    // 2. Handle Arrays
    if (Array.isArray(obj)) {
        return obj.map(deepToBigInt);
    }

    // 3. Handle Objects
    return Object.fromEntries(
        Object.entries(obj).map(([key, value]) => [key, deepToBigInt(value)])
    );
}

async function prepareBatch(folder) {
    // 1. Setup paths
    const inputPath = path.join(__dirname, `../zk/${folder}/input.json`);
    const wasmPath = path.join(__dirname, `../zk/${folder}/circuit.wasm`);
    const zkeyPath = path.join(__dirname, `../zk/${folder}/circuit_final.zkey`);
    const saveDir = path.join(__dirname, `../zk/${folder}/`);

    console.log(inputPath);

    // 2. Read and parse input file
    const rawData = await fs.readFile(inputPath, "utf8");
    const input = deepToBigInt(JSON.parse(rawData)); // <--- Everything is now BigInt

    console.log("Generating proof for epoch:", input.epoch.toString());

    // 3. Generate the Proof
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        input,
        wasmPath,
        zkeyPath
    );

    // 4. Save files to saveDir (using JSON.stringify for formatting)
    // We use null, 2 to make the JSON human-readable
    await fs.writeFile(path.join(saveDir, 'proof.json'), JSON.stringify(proof, null, 2));
    await fs.writeFile(path.join(saveDir, 'public.json'), JSON.stringify(publicSignals, null, 2));

    // 5. Format outputs for return
    const pB = [
        proof.pi_b[0][1], // X Real
        proof.pi_b[0][0], // X Imaginary
        proof.pi_b[1][1], // Y Real
        proof.pi_b[1][0]  // Y Imaginary
    ];

    return { 
        pA: proof.pi_a.slice(0, 2), 
        pB, 
        pC: proof.pi_c.slice(0, 2), 
        publicSignals 
    };
}

module.exports = { prepareBatch };