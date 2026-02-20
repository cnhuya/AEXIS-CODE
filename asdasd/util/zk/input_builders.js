const fs = require("fs");
const path = require("path");
const { buildPoseidon, buildEddsa } = require("circomlibjs");
const { getState } = require("../state.js");
const { generateIndex, prepareBalances, PoseidonMerkleTree } = require("./zk_builders.js");
const { strToField, extractEventData, split256BitValue, convertChainStrToID, packSlot8, convertTokenStrToAddress, convertVaultAddrToStr, convertVaultStrToAddress} = require("../global_util.js");
const { get_consensus_vote_data } = require("../fetchers.js");

async function build_input(type, data) {

    //let data = getState(type);

    //console.log(data);

    if (!data) {
        console.log("No data provided for input building.");
        return;
    }

    console.log("Building input for type:", type);

    if (type === "validators") {
        await build_validators_input(data);
    } else if (type === "relayer") {
        await build_balances_input(data);
    } else if (type === "variables") {
        await build_variables_input(data);
    } else {
        console.log("Unsupported input build type:", type);
    }
}

async function build_validators_input(data) {
    try {
        const CIRCUIT_N_VALIDATORS = 16;
        
        if (!data.tree) {
            console.error("Tree not initialized. Skipping input build.");
            return;
        }

        const inputs = {
            currentValidatorRoot: data.currentRoot.toString(),
            newValidatorRoot: data.newRoot.toString(),
            epoch: data.epoch.toString(),
            validatorPubKeysX: [],
            validatorPubKeysY: [],
            isSigned: [],
            signaturesR8x: [],
            signaturesR8y: [],
            signaturesS: [],
            valPathElements: [],
            valPathIndices: []
        };

        // 1. Create a Signature Map using the PubKey as the key
        // Format: "pubKeyX_pubKeyY"
        const sigMap = {};
        console.log("sigs:", data.sigs);
        if (data.sigs) {
            data.sigs.forEach(sig => {
                const key = `${sig.pub_key_x.toString()}_${sig.pub_key_y.toString()}`;
                sigMap[key] = sig;
            });
        }

        // 2. Iterate through the validators list (the ones in the Merkle Tree)
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            // Generate Merkle proof for this position
            const proof = data.tree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const v = data.validators[i];

            if (v) {
                // Construct the key to look up the signature
                const lookupKey = `${v.pub_key_x.toString()}_${v.pub_key_y.toString()}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());

                if (sig) {
                    // Match found: this validator signed
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    // No signature found for this pubkey
                    inputs.isSigned.push(0);
                    inputs.signaturesR8x.push("0");
                    inputs.signaturesR8y.push("0");
                    inputs.signaturesS.push("0");
                }
            } else {
                // Empty slot in the validator set
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("0");
                inputs.signaturesS.push("0");
            }
        }

        const inputPath = path.join(__dirname, '../../zk/validators/input.json');
        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready (Matched via PubKeys)");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

async function build_balances_input(data) {
    console.log(data)   ;
    try {
        const CIRCUIT_N_VALIDATORS = 16;

        console.log(data.event);
        let x = extractEventData(data.event, ["index", "nonce", "validator_root", "old_root", "new_root", "receiver", "chain", "token", "provider", "additional_outflow", "total_outflow", "timestamp"]);
        //console.log(x);
        let userAddress = split256BitValue(x.receiver);
        let storageID = strToField(x.token);
        let vaultAddress = strToField(x.provider);

        let chainTo = await convertChainStrToID(x.chain);
        const index = await generateIndex([userAddress.low, userAddress.high, storageID, chainTo], 256);
        
        //const oldLeaf = poseidon([userAddress.low, userAddress.high, x.total_outflow, storageID.low, storageID.high]);
        //data.balTree.update(index, oldLeaf); // Ensure we are starting from the right place

        // 2. Now generate proof for the OLD state
        //const proof2 = data.balTree.generateProof(index);
        console.log("Validator root Check1:", x.validator_root);
        console.log("Validator root Check2:", data.valTree.getRoot());

        console.log("oldAccountRoot root:", x.old_root);
        console.log("newAccountRoot root:", x.new_root);

        const chainToBI = BigInt(chainTo);
        const amountBI = BigInt(x.additional_outflow);
        const indexBI = BigInt(x.index); // Use the index from your tree logic
        const nextNonceBI = BigInt(x.nonce) + 1n; // Use 1n for BigInt addition

        let packed = packSlot8(chainToBI, amountBI, indexBI, nextNonceBI);

        const inputs = {
            currentValidatorRoot: x.validator_root.toString(),
            oldAccountRoot: x.old_root.toString(),
            newAccountRoot: x.new_root.toString(),
            //epoch: data.epoch ? data.epoch.toString() : "0",
            chainID: chainTo.toString(),
            userAddress_L: userAddress.low.toString(),
            userAddress_H: userAddress.high.toString(),
            storageID: storageID.toString(),
            packedTxData: packed.toString(),
            vaultAddress: vaultAddress.toString(),
            amount: x.additional_outflow.toString(),
            oldBalance: x.total_outflow.toString(),
            oldNonce: x.nonce.toString(),
            index: x.index.toString(),
            validatorPubKeysX: [],
            validatorPubKeysY: [],
            validatorStakes: [],
            isSigned: [],
            signaturesR8x: [],
            signaturesR8y: [],
            signaturesS: [],
            valPathElements: [],
            valPathIndices: [],
            accountPathElements: [],
            accountPathIndices: [],

        };

        // 1. Create a Signature Map using the PubKey as the key
        const sigMap = {};
        if (data.validators_sig) {
            data.validators_sig.forEach(sig => {
                // Ensure we use the exact keys from your provided data object
                const key = `${sig.pub_key_x}_${sig.pub_key_y}`;
                sigMap[key] = sig;
            });
        }

        // 2. Iterate through the validators list
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            // Merkle Proofs
            const proof = data.valTree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const v = data.validators[i];

            if (v) {
                // Use underscores to match your data structure: v.pub_key_x
                const lookupKey = `${v.pub_key_x}_${v.pub_key_y}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked ? v.staked.toString() : (v.weight ? v.weight.toString() : "0"));

                if (sig) {
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    inputs.isSigned.push(0);
                    inputs.signaturesR8x.push("0");
                    inputs.signaturesR8y.push("0");
                    inputs.signaturesS.push("0");
                }
            } else {
                // Padding for empty slots
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.validatorStakes.push("0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("0");
                inputs.signaturesS.push("0");
            }
        }
        // 1. Find the index of the specific user being updated
        console.log("index1:", index);
        // 2. Generate ONE proof for that ONE index
        const proof = data.balTree.generateProof(index); 

        // 3. Assign the arrays directly (do not use a loop to push 256 times)
        inputs.accountPathElements = proof.siblings.map(s => s.toString());
        inputs.accountPathIndices = proof.indices.map(idx => idx.toString());

        // Ensure these arrays have exactly 256 elements
        console.log(inputs.accountPathElements.length); // Should be 256


        const inputPath = path.join(__dirname, '../../zk/balances/input.json');
        console.log(inputPath);
        // Ensure directory exists (optional but recommended)
        const dir = path.dirname(inputPath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready (Matched via PubKeys)");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

async function build_test_input(taskData) {
    const { 
        pathElements, 
        pathIndices, 
        oldRoot, 
        newRoot, 
        newBalance,  // Captured from StateManager
        newNonce,    // Captured from StateManager
        oldNonce,    // Captured from StateManager
        valTree, 
        sigs, 
        validators,
        event 
    } = taskData;

    try {
        const CIRCUIT_N_VALIDATORS = 16;
        console.log(taskData);
        // 1. Extract Event Fields
        let x = extractEventData(event, [
            "addr", "chain", "token", "provider", "additional_outflow", "total_outflow", "validator_root"
        ]);
        let userAddress = split256BitValue(x.addr);
        let storageID = strToField(x.token);
        let vaultAddress = strToField(x.provider);
                console.log("testwwqeweqwe");
        let chainTo = await convertChainStrToID(x.chain);
        // 2. Prepare Packed Data (Slot 8)
        // Ensure we use the exact values that transition from oldRoot -> newRoot
        const chainToBI = BigInt(chainTo);
        const amountBI = BigInt(x.additional_outflow);
        const nextNonceBI = BigInt(newNonce); // Using snapshot value
        let packed = packSlot8(chainToBI, amountBI, nextNonceBI);

        // 3. Initialize Inputs
    // 3. Initialize Inputs with safety checks
        const inputs = {
            currentValidatorRoot: x.validator_root.toString(),
            oldAccountRoot: oldRoot.toString(),
            newAccountRoot: newRoot.toString(),
            chainID: chainTo.toString(),
            userAddress_L: userAddress.low.toString(),
            userAddress_H: userAddress.high.toString(),
            storageID: storageID.toString(),
            packedTxData: packed.toString(),
            vaultAddress: vaultAddress.toString(),
            amount: x.additional_outflow.toString(),
            oldBalance: x.total_outflow.toString(),
            oldNonce: oldNonce.toString(),
            
            validatorPubKeysX: [],
            validatorPubKeysY: [],
            validatorStakes: [],
            isSigned: [],
            signaturesR8x: [],
            signaturesR8y: [],
            signaturesS: [],
            valPathElements: [],
            valPathIndices: [],
            
            // Fix: Add fallback to empty array to prevent .map() crash
            accountPathElements: (pathElements || []).map(s => s.toString()),
            accountPathIndices: (pathIndices || []).map(idx => idx.toString()),
        };

        const sigMap = {};
        if (sigs) {
            sigs.forEach(sig => {
                const key = `${sig.pub_key_x}_${sig.pub_key_y}`;
                sigMap[key] = sig;
            });
        }

        // 5. Build Validator Proofs
        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            const proof = valTree.generateProof(i); 
            // Note: Ensure valTree.generateProof returns the correct key names
            inputs.valPathElements.push(proof.siblings.map(s => s.toString())); 
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const v = validators[i];
            if (v) {
                const lookupKey = `${v.pub_key_x}_${v.pub_key_y}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                // FIX: Use 'staked' as seen in your logs
                inputs.validatorStakes.push(v.staked ? v.staked.toString() : "0");

                if (sig) {
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    fillEmptySig(inputs);
                }
            } else {
                // Fill padding for empty validator slots
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.validatorStakes.push("0");
                fillEmptySig(inputs);
            }
        }

        // Use path.resolve to be extra safe with worker directory context
        const fileName = `input.json`;
        const dirPath = path.resolve(__dirname, '../../zk/balances/');

        // Ensure directory exists
        if (!fs.existsSync(dirPath)){
            fs.mkdirSync(dirPath, { recursive: true });
        }

        const inputPath = path.join(dirPath, fileName);
        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));

        return inputPath;
        
    } catch (error) {
        console.error("Failed to build circuit input in worker:", error);
        throw error;
    }
}

async function build_variables_input(data) {
    try {
        const N_VALIDATORS = 16;
        const VAL_DEPTH = 4; 
        const VAR_DEPTH = 16;

        console.log("Building ZK Input for Variable:", data.variable.name);


        const inputs = {
            currentValidatorRoot: data.valTree.getRoot().toString(),
            oldVariableRoot: BigInt(data.variable.oldRoot).toString(),
            newVariableRoot: BigInt(data.variable.newRoot).toString(),
            variableHeader: strToField(data.variable.header).toString(),
            variableName: strToField(data.variable.name).toString(),
            
            // FIX 1: Use BigInt/Numbers for data values. 
            // strToField would turn "50" into ASCII bytes, but the tree uses the value 50.
            oldVariableData: BigInt(data.variable.oldData || 0).toString(),
            newVariableData: BigInt(data.variable.newData).toString(),

            variablePathElements: [],
            variablePathIndices: [],

            validatorPubKeysX: [],
            validatorPubKeysY: [],
            validatorStakes: [],
            isSigned: [],
            signaturesR8x: [],
            signaturesR8y: [],
            signaturesS: [],
            valPathElements: [],
            valPathIndices: []
        };
/*[Tree] Initialized slot 0 for QiaraTokens with empty leaf 1265956024647435409834094082752946274485075080365918701856778197115170720716
[Tree] updated slot 0 for QiaraTokens | TRANSFER_FEE with final leaf 302922231552137812915605815580144240111992371715841795583005079163904643801, data: 50
        
Calculated Leaf (JS): 1265956024647435409834094082752946274485075080365918701856778197115170720716
New Calculated Leaf (JS): 19654845284841762945156096929294935330964530376330475310065389081778816321773 */

/*    [Tree] Initialized slot 0 for QiaraTokens with empty leaf 1265956024647435409834094082752946274485075080365918701856778197115170720716
    [Tree] updated slot 0 for QiaraTokens | TRANSFER_FEE with final leaf 302922231552137812915605815580144240111992371715841795583005079163904643801, data: 50

    [Tree] checking slot 0 for QiaraTokens | TRANSFER_FEE with final leaf 1265956024647435409834094082752946274485075080365918701856778197115170720716, data: 0
    [Tree] new checking slot 0 for QiaraTokens | TRANSFER_FEE with final leaf 19654845284841762945156096929294935330964530376330475310065389081778816321773, data: 50*/

    
/*Username = rolljokes
Password = friends1 crazy acc, iron, yep qiyana rolljokes#EUNE RLY GOOD ACC WAZZ */
    
/*Username = zvaniture
Password = Bicikla1 active, iron, yep qiyana */
        inputs.variablePathElements = data.variable.storedPath;

        // Ensure we are passing numeric 0, not the string "0x0"
        const oldVal = data.variable.oldData;
        const cleanOldData = (oldVal === undefined || oldVal === "0x0" || oldVal === "0") ? 0n : BigInt(oldVal);
        console.log("data", cleanOldData);
        const poseidon = await buildPoseidon();
        const expectedLeaf = poseidon([strToField(data.variable.header), strToField(data.variable.name), cleanOldData]);
        const newexpectedLeaf = poseidon([strToField(data.variable.header), strToField(data.variable.name),  BigInt(data.variable.newData)]);
        console.log(data.variable);
        const leafIndex = parseInt(data.variable.index);
        console.log(`[Tree] checking slot ${leafIndex} for ${data.variable.header} | ${data.variable.name} with final leaf ${poseidon.F.toString(expectedLeaf)}, data: ${(cleanOldData)}`);
        console.log(`[Tree] new checking slot ${leafIndex} for ${data.variable.header} | ${data.variable.name} with final leaf ${poseidon.F.toString(newexpectedLeaf)}, data: ${BigInt(data.variable.newData)}`);

        inputs.oldVariableData = cleanOldData.toString();
        inputs.newVariableData = BigInt(data.variable.newData).toString();

        // --- 1. Generate Variable Merkle Proof ---
        const varProof = data.varTree.generateProof(leafIndex);
        console.log(data.variable.storedPath);
        // Ensure path elements are strings
        inputs.variablePathElements = varProof.siblings.map(s => s.toString());

        //Manually calculate Path Indices as bits (LSB to MSB)
        const pathIndices = [];
        for (let i = 0; i < VAR_DEPTH; i++) {
            const bit = (leafIndex >> i) & 1; // Recalculate from the index
            pathIndices.push(bit.toString());
        }
        inputs.variablePathIndices = pathIndices;

        // --- 2. Validator Logic ---
        const sigMap = {};
        if (data.sigs) {
            data.sigs.forEach(sig => {
                const key = `${sig.pub_key_x.toString()}_${sig.pub_key_y.toString()}`;
                sigMap[key] = sig;
            });
        }

        for (let i = 0; i < N_VALIDATORS; i++) {
            // Generate proof for the validator's position in the validator tree
            const vProof = data.valTree.generateProof(i);
            inputs.valPathElements.push(vProof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(vProof.indices.map(idx => idx.toString()));

            const v = data.validators[i];
            if (v) {
                const lookupKey = `${v.pub_key_x.toString()}_${v.pub_key_y.toString()}`;
                const sig = sigMap[lookupKey];

                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked.toString());

                if (sig) {
                    inputs.isSigned.push(1);
                    inputs.signaturesR8x.push(sig.s_r8x.toString());
                    inputs.signaturesR8y.push(sig.s_r8y.toString());
                    inputs.signaturesS.push(sig.s.toString());
                } else {
                    // Assuming fillEmptySig is a helper that pushes "0" to sig arrays
                    fillEmptySig(inputs);
                }
            } else {
                inputs.validatorPubKeysX.push("0");
                inputs.validatorPubKeysY.push("0");
                inputs.validatorStakes.push("0");
                fillEmptySig(inputs);
            }
        }

        const inputPath = path.join(__dirname, '../../zk/variables/input.json');
        fs.writeFileSync(inputPath, JSON.stringify(inputs, null, 2));
        console.log("✅ Successfully wrote input.json to:", inputPath);

    } catch (error) {
        console.error("🚨 Input Builder Error:", error);
    }
}

function fillEmptySig(inputs) {
    inputs.isSigned.push(0);
    inputs.signaturesR8x.push("0");
    inputs.signaturesR8y.push("0");
    inputs.signaturesS.push("0");
}


module.exports = {build_input, build_test_input};