
process.env.NODE_ENV = 'production';
const { parentPort } = require('worker_threads');
const { PoseidonMerkleTree } = require("./zk/zk_builders.js");
const path = require('path');
const fs = require('fs');
parentPort.on('message', async (taskData) => {
    try {
        // 1. Destructure the snapshot taken by the StateManager
        const { 
            pathElements, 
            pathIndices, 
            oldRoot, 
            newRoot, 
            newBalance, 
            newNonce, 
            oldNonce,
            valTreeData, 
            sigs, 
            validators,
            event 
        } = taskData;
        const { buildPoseidon } = require("circomlibjs");
        const poseidon = await buildPoseidon();
        const oldRootStr = oldRoot?.toString() || "0";
        const newRootStr = newRoot?.toString() || "0";
        console.log(`[Worker] Starting proof for Root transition: ${oldRootStr.slice(0,10)}... -> ${newRootStr.slice(0,10)}...`);
        const valTree = await PoseidonMerkleTree.deserialize(taskData.valTreeData, poseidon);
        // 2. Build the Circom witness inputs
        const { build_test_input } = require("./zk/input_builders.js");
        await build_test_input({
            ...taskData,
            valTree: valTree
        });

        // 3. Execute SnarkJS (The heavy CPU task)
        // This usually involves 'snarkjs groth16 prove' logic inside prepareBatch
        const { prepareBatch } = require("./prover.js");
        const proof = await prepareBatch("balances");

        // 4. Local Validation (Optional but recommended before hitting the chain)
        // This checks if the proof is mathematically valid against the verification key
        // await Validate_proof(BRIDGE_CONFIG, event, proof); 

        // 5. Signal completion back to the main thread
        parentPort.postMessage({ 
            success: true, 
            tx_hash: event.tx_hash, 
            proof: proof,
            roots: { old: oldRoot, new: newRoot } 
        });

    } catch (error) {
        console.error(`[Worker Error]: ${error.message}`);
        parentPort.postMessage({ 
            success: false, 
            error: error.message, 
            tx_hash: taskData.event?.tx_hash 
        });
    }
});