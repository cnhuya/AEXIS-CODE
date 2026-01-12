const Fastify = require('fastify');
const snarkjs = require("snarkjs");
const fs = require("fs");
const { buildPoseidon } = require("circomlibjs");
const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { poseidon } = require("poseidon-lite");
const { send } = require('process');
let supraClient;

async function initialize() {
    supraClient = await SupraClient.init(
        "https://rpc-testnet.supra.com", // example URL
        { /* your config */ }
    );
    
    // Now you can call validate or other logic
    // await validate(id, value);
}




 function serializeU8Vector(nums) {
  const lengthBytes = encodeULEB128(nums.length);
  const valueBytes = nums.flatMap(num => Array.from(BCS.bcsSerializeU8(num)));
  return Uint8Array.from([...lengthBytes, ...valueBytes]);
}

 function encodeULEB128(value) {
  const bytes = [];
  do {
    let byte = value & 0x7f;
    value >>>= 7;
    if (value !== 0) {
      byte |= 0x80;
    }
    bytes.push(byte);
  } while (value !== 0);
  return bytes;
}

class PoseidonMerkleTree {
    constructor(leaves) {
        // Ensure all leaves are BigInts
        this.leaves = leaves.map(leaf => BigInt(leaf));
        this.tree = [];
        this._rootBuffer = null;
        this.buildTree();
    }

    buildTree() {
        let currentLevel = this.leaves;
        this.tree.push(currentLevel);

        while (currentLevel.length > 1) {
            if (currentLevel.length % 2 !== 0) {
                currentLevel.push(currentLevel[currentLevel.length - 1]);
            }
            let nextLevel = [];
            for (let i = 0; i < currentLevel.length; i += 2) {
                const hash = poseidon([currentLevel[i], currentLevel[i + 1]]);
                nextLevel.push(hash);
            }
            this.tree.push(nextLevel);
            currentLevel = nextLevel;
        }

        // Final root BigInt
        const rootBigInt = currentLevel[0];
        
        // 2026-01-09 Instruction: Reverse buffer (Big Endian -> Little Endian)
        const buf = Buffer.alloc(32);
        let temp = rootBigInt;
        for (let i = 0; i < 4; i++) {
            const limb = temp & 0xFFFFFFFFFFFFFFFFn;
            buf.writeBigUInt64LE(limb, i * 8);
            temp >>= 64n;
        }
        this._rootBuffer = buf;
    }

    get root() {
        return this._rootBuffer;
    }
}

const privateKeyHex = "6cb168ab2ba30211d0b0e52b16acfe1a9438457088732f66079c6635f00bea50"; 
const senderAcc = new SupraAccount(Buffer.from(privateKeyHex.replace("0x", ""), "hex"));

// --- UTILS ---
function to32Bytes(decimalStr) {
    // 1. Convert to Hex and pad to 64 chars (32 bytes)
    let hex = BigInt(decimalStr).toString(16).padStart(64, '0');
    
    // 2. Create Buffer
    let buf = Buffer.from(hex, 'hex');
    
    // 3. REVERSE the buffer (Big Endian -> Little Endian)
    // Most Move BN254 implementations expect Little Endian bytes
    return buf.reverse(); 
}

// Format for Supra Move Tool (vector of vector of u8)
// Example: hex:[0x1122, 0x3344]
function toHexVectorArg(hexArray) {
    return `hex:[${hexArray.join(",")}]`;
}

let data;

// --- CORE LOGIC ---

    async function fetchEvent(){

        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/events/0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax4::BridgeUpdateEvent', {
            method: 'GET',
            headers: {
            "Accept": "*/*"
            },
        });
        data = await response.json();
    }

    async function get_allVariables() {
        try {
            const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
                method: 'POST',
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    "function": "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax8::return_variables",
                    "type_arguments": [], 
                    "arguments": []
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const body = await response.json();
            
            // Supra RPC returns the values in the 'result' array
            // We use optional chaining (?.) to handle cases where the result might be missing
            const resultData = body?.result;

            // Check if the result is empty or not an array
            if (!resultData || !Array.isArray(resultData) || resultData.length === 0) {
                console.warn("Variables table is empty. Returning [0] to initialize Merkle Tree.");
                // Returning a default zero value allows the Merkle Tree to have at least one leaf
                return ["0"]; 
            }

            // If your 'return_variables' returns a vector of u256 or structs, 
            // we map them here. If it's a simple vector, 'item' is the value.
            const variables = resultData.map(item => {
                if (typeof item === 'object' && item !== null) {
                    return item.value || item[0] || "0";
                }
                return item.toString();
            });

            console.log("Fetched Variables:", variables);

            // Update your global data object safely
            if (typeof data !== 'undefined') {
                data.allVariables = variables;
            }

            return variables;

        } catch (error) {
            console.error("Failed to fetch variables:", error);
            // Always return an array so PoseidonMerkleTree.map() doesn't throw a TypeError
            return ["0"]; 
        }
    }

    async function get_epoch() {
        try {
            const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
                method: 'POST',
                headers: {
                    "Content-Type": "application/json"
                },
                body: JSON.stringify({
                    // The function path must be a string
                    "function": "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax4::return_epoch",
                    // Supra RPC expects arrays for these fields
                    "type_arguments": [], 
                    "arguments": []
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const result = await response.json();
            
            // Ensure 'data' is defined in your outer scope or passed as a reference
            data.epoch = result;
            
            return result; 
        } catch (error) {
            console.error("Failed to fetch variables:", error);
        }
    }

    async function calculateValidatorRoot(validatorPubKeys) {
        // validatorPubKeys should be an array of 64 public keys (BigInt or Hex)
        const poseidon = await buildPoseidon();
        const F = poseidon.F;

        // 1. Prepare 64 leaves. Circom circuit expects exactly 64.
        // If you have fewer than 64 validators, the rest must be 0.
        let leaves = new Array(64).fill(BigInt(0));
        
        for (let i = 0; i < validatorPubKeys.length; i++) {
            // We use the raw pubkey as the leaf, just like the circuit: 
            // valTree[i] <== validatorPubKeys[i];
            leaves[i] = BigInt(validatorPubKeys[i]);
        }

        // 2. Build the tree
        // Note: Use a MerkleTree implementation that uses Poseidon(2)
        const tree = new MerkleTree(leaves, (a, b) => {
            const hash = poseidon([a, b]);
            return F.toObject(hash);
        });

        const root = tree.getRoot();
        
        // 3. Apply your personalization rule (Little Endian reversal)
        return to32Bytes(root);
    }

    async function calculateSigSummary() {
        const poseidon = await buildPoseidon();
        let signedIndices = data.validators.map(v => v.index);
        // 1. Create a BigInt bitmask for 64 validators
        let bitmask = BigInt(0);
        
        // signedIndices is an array of integers, e.g., [0, 2, 15]
        signedIndices.forEach(index => {
            if (index >= 0 && index < 64) {
                // Set the n-th bit to 1
                bitmask |= (BigInt(1) << BigInt(index));
            }
        });

        // 2. Hash the bitmask
        // Poseidon expects an array of inputs; here we have 1 input
        const hash = poseidon([bitmask]);
        const sigSummaryInt = poseidon.F.toObject(hash);

        // 3. Apply your personalization rule: 
        // Convert to 32-byte hex string with reversed buffer (Little Endian)
        return to32Bytes(sigSummaryInt);
    }


function buildPayload(root, variable_id, value, epoch) {
    // For Ed25519 signing in Move/Sui, you usually need to serialize
    // the data as a contiguous byte array
    
    // Convert root to Uint8Array if it's a Buffer
    const rootBytes = root instanceof Buffer ? new Uint8Array(root) : root;
    
    // Check the type of value to determine how to serialize it
    let valueBytes;
    
    // If T is u64 (most likely for oracle values)
    if (typeof value === 'number' || typeof value === 'bigint' || typeof value === 'string') {
        valueBytes = BCS.bcsSerializeUint64(BigInt(value));
    } 
    // If you need to support other types
    else if (typeof value === 'boolean') {
        valueBytes = BCS.bcsSerializeBool(value);
    }
    else {
        // Try bcsToBytes as a fallback
        valueBytes = BCS.bcsToBytes(value);
    }
    
    // Serialize other fields
    const variableIdBytes = BCS.bcsSerializeUint64(BigInt(variable_id));
    const epochBytes = BCS.bcsSerializeUint64(BigInt(epoch));
    
    // Combine all bytes
    const totalLength = rootBytes.length + variableIdBytes.length + valueBytes.length + epochBytes.length;
    const payload = new Uint8Array(totalLength);
    
    let offset = 0;
    payload.set(rootBytes, offset);
    offset += rootBytes.length;
    payload.set(variableIdBytes, offset);
    offset += variableIdBytes.length;
    payload.set(valueBytes, offset);
    offset += valueBytes.length;
    payload.set(epochBytes, offset);
    
    return payload;
}

async function validate(variable_name, variable_id, newValue) {
    
    await initialize();
    try {
        const tree = new PoseidonMerkleTree(await get_allVariables());
        const root = tree.root; 
        const epoch = 0;

        // 1. Get the 32-byte buffer directly (Reversed to Little Endian per your instructions)
        // Ensure to32Bytes(newValue) returns a single 32-byte Buffer or Uint8Array
        const valueBytes = to32Bytes(newValue); 

        // 2. Prepare the signing message
        // Use standard Uint8Array spreads to avoid Buffer.concat "list" errors
        const payload = buildPayload(root, variable_id, newValue, epoch);
        // Sign payload
        const signature = await senderAcc.signBuffer(payload);
        const serialized_value = serializeU8Vector(Array.from(valueBytes));
        const serialized_message = serializeU8Vector(Array.from(payload));
        const serialized_signature = serializeU8Vector(
        Array.from(signature.toUint8Array())
        );
        console.log(serialized_signature);
        console.log(serialized_value);
        console.log(Uint8Array.from(valueBytes));
        // 3. Build the Transaction Payload
        // We pass the raw Uint8Arrays. The SDK's createRawTxObject 
        // will handle the internal serialization.
        const txPayload = [
            serialized_message,
            BCS.bcsSerializeUint64(variable_id),
            serialized_value, // The 32-byte u256
            BCS.bcsSerializeStr(variable_name),
            serialized_signature
        ];

        // 4. Transaction Setup

        const senderAddr = senderAcc.address();
       // const accInfo = await supraClient.getAccountInfo(senderAddr);
        //console.log(txPayload);
        const rawTx = await supraClient.createSerializedRawTxObject(
            senderAddr,
            272,
            "6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1",
            "Qiarax8",
            "validate_and_vote",
            [], 
            txPayload
        );
        console.log(root.toString('hex'));
        // 5. Sign and Send
        //SupraClient.signSupraTransaction(senderAcc, rawTx);
        return await supraClient.sendTxUsingSerializedRawTransaction(senderAcc, rawTx);
        

    } catch (error) {
        console.error("Validation transaction failed:", error);
        throw error;
    }
}

console.log(validate("Hi",3, 11));

async function generateInputJson(variableId, newValue, allVariables, epoch, validatorPubKeys) {
    // 1. Build the tree locally in JS
    const tree = new PoseidonMerkleTree(allVariables); 
    
    // 2. Get the proof (the siblings)
    const { siblings, indices } = tree.generateProof(variableId);

    // 3. Construct the input object using the to32Bytes rule
    const input = {
        "validatorRoot": to32Bytes(calculateValidatorRoot(validatorPubKeys)),
        "epoch": epoch.toString(),
        "variableID": variableId.toString(),
        "newValue": newValue.toString(),
        "poseidonRoot": to32Bytes(tree.root),
        
        // Private Inputs
        "validatorPubKeys": validatorPubKeys.map(pk => to32Bytes(pk)),
        "sigSummary": await calculateSigSummary(), // Uses to32Bytes inside
        
        // Map sibling hashes through your reversal rule
        "pathElements": siblings.map(s => to32Bytes(s)),
        "pathIndices": indices
    };

    return JSON.stringify(input, null, 2);
}

async function generateFullAptosTransaction() {
    await buildInput();
    const circuitInputs = JSON.parse(fs.readFileSync("input.json"));
    
    try {
        const wasmPath = "./zk/circuit.wasm";
        const zkeyPath = "./zk/circuit_final.zkey";
        
        console.log("⏳ Generating SNARK proof...");
        const { proof, publicSignals } = await snarkjs.groth16.fullProve(
            circuitInputs, wasmPath, zkeyPath
        );

        // --- 1. FORMAT PROOF POINTS (Raw Hex, no 0x here) ---
        const pA_hex = Buffer.concat([
            to32Bytes(proof.pi_a[0]), 
            to32Bytes(proof.pi_a[1])
        ]).toString('hex');


        const pC_hex = Buffer.concat([
            to32Bytes(proof.pi_c[0]), 
            to32Bytes(proof.pi_c[1])
        ]).toString('hex');

        // G2 Point re-ordering for Move BN254
        const pB_hex = Buffer.concat([
    to32Bytes(proof.pi_b[0][0]), // X Real
    to32Bytes(proof.pi_b[0][1]), // X Imaginary
    to32Bytes(proof.pi_b[1][0]), // Y Real
    to32Bytes(proof.pi_b[1][1])  // Y Imaginary
        ]).toString('hex');

        console.log(`✅ pA Length: ${pA_hex.length / 2} bytes`);
        console.log(`✅ pB Length: ${pB_hex.length / 2} bytes`);
        console.log(`✅ pC Length: ${pC_hex.length / 2} bytes`);

        // --- 2. FORMAT PUBLIC SIGNALS ---
        const publicSignalsDec = publicSignals.map(sig => BigInt(sig).toString());
        // Standard array format: [val1,val2]
        const signalsArg = `[${publicSignalsDec.join(",")}]`;

        // --- 3. FORMAT CALL DATA (If needed by your Move function) ---
        const callData1 = "0x" + Buffer.from("call_data_1").toString('hex');
        const callData2 = "0x" + Buffer.from("call_data_2").toString('hex');
        const allCallsArg = `vector<vector<u8>>:[${callData1},${callData2}]`;

        // --- 4. THE COMMAND (Fixing the 0x0x and u256 formatting) ---
        const command = [
            `supra move tool run`,
            `--function-id 0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::QiaraZK_testV4::verify_with_hardcoded_vk2`,
            `--args`,
            `hex:0x${pA_hex}`, 
            `hex:0x${pB_hex}`,
            `hex:0x${pC_hex}`,
            `u256:"${signalsArg}"`, // Removed quotes, kept colon
         //   `${allCallsArg}`      // Ensure your Move function has this 5th argument!
        ].join(" ");

        console.log("\n--- GENERATED SUPRA MOVE COMMAND ---");
        console.log(command);

    } catch (error) {
        console.error("❌ Error:", error);
    }
}

//generateFullAptosTransaction();