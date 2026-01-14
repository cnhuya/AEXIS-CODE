const Fastify = require('fastify');
const snarkjs = require("snarkjs");
const fs = require("fs");
const { buildPoseidon } = require("circomlibjs");
const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { poseidon } = require("poseidon-lite");
const { send } = require('process');
const { prepareBatch } = require("./prover.js");
const HISTORY_FILE = './message_history.json';
let supraClient;

const nValidators = 64;
const treeDepth = 10;

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
    constructor(leaves, poseidon, depth = 10) {
        this.poseidon = poseidon;
        const F = poseidon.F;
        this.depth = depth;
        
        // 1. Pad leaves to the full capacity of the tree (2^depth)
        // Use 0 as the default value for empty slots
        let fullLeaves = [...leaves];
        while (fullLeaves.length < Math.pow(2, depth)) {
            fullLeaves.push("0");
        }

        // 2. Hash leaves: Hash(index, value) to match Circom leafHasher
        // Inside constructor
        this.leaves = fullLeaves.map((val, i) => {
            // val can be BigInt (from variables) or String "0" (from padding)
            const v = BigInt(val) % poseidon.F.p; 
            // MUST match Circom: Poseidon(variableID, currentValue)
            return F.toObject(this.poseidon([BigInt(i), v])); 
        });

        
        this.layers = []; 
        this.buildTree();
    }

    buildTree() {
        let currentLayer = this.leaves;
        this.layers.push(currentLayer);

        // Force the tree to climb to the specified depth
        for (let d = 0; d < this.depth; d++) {
            let nextLayer = [];
            for (let i = 0; i < currentLayer.length; i += 2) {
                const left = currentLayer[i];
                // In a perfectly padded tree, right will always exist
                const right = currentLayer[i + 1]; 
                
                const hash = this.poseidon([left, right]);
                nextLayer.push(this.poseidon.F.toObject(hash));
            }
            this.layers.push(nextLayer);
            currentLayer = nextLayer;
        }
    }

    generateProof(index) {
        let siblings = [];
        let indices = [];
        let currentIndex = index;

        // Iterate exactly 'depth' times
        for (let i = 0; i < this.depth; i++) {
            let layer = this.layers[i];
            let isRightNode = currentIndex % 2 === 1;
            let siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;

            siblings.push(layer[siblingIndex]);
            indices.push(isRightNode ? 1 : 0);

            currentIndex = Math.floor(currentIndex / 2);
        }

        return { siblings, indices };
    }

    getRoot() {
        return this.layers[this.layers.length - 1][0];
    }
}

const privateKeyHex = "6cb168ab2ba30211d0b0e52b16acfe1a9438457088732f66079c6635f00bea50"; 
const senderAcc = new SupraAccount(Buffer.from(privateKeyHex.replace("0x", ""), "hex"));
let data = {
    messageHistory: [],
    epoch: 0,
    allVariables: []
};
function loadHistory() {
    if (fs.existsSync(HISTORY_FILE)) {
        try {
            const content = fs.readFileSync(HISTORY_FILE, 'utf8');
            // Check if file is empty
            if (content.trim().length > 0) {
                const saved = JSON.parse(content);
                data.messageHistory = Array.isArray(saved.messageHistory) ? saved.messageHistory : [];
            }
        } catch (e) {
            console.error("Error reading history file, initializing fresh:", e.message);
            data.messageHistory = [];
        }
    }
}

// Call this immediately
loadHistory();
// --- UTILS ---
function to32Bytes(input) {
    let hex;
    if (Buffer.isBuffer(input)) {
        hex = input.toString('hex');
    } else if (typeof input === 'string') {
        hex = input.startsWith('0x') ? input.slice(2) : input;
    } else {
        hex = BigInt(input).toString(16);
    }

    // pad to 32 bytes
    const buf = Buffer.from(hex.padStart(64, '0'), 'hex');

    // reverse to little endian if required
    return Uint8Array.from(buf.reverse());
}

    async function get_allVariables(retries = 3) {
        for (let i = 0; i < retries; i++) {
            try {
                // Using AbortController to manage our own timeout
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 second timeout

                const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
                    method: 'POST',
                    headers: { 
                        "Content-Type": "application/json",
                        "User-Agent": "Mozilla/5.0" // Mimic a browser/common client
                    },
                    signal: controller.signal,
                    body: JSON.stringify({
                        "function": "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax8::return_variables",
                        "type_arguments": [],
                        "arguments": []
                    })
                });

                clearTimeout(timeoutId);

                if (!response.ok) throw new Error(`HTTP ${response.status}`);

                const body = await response.json();
                const rawDataArray = body?.result?.[0]?.data;

                if (!rawDataArray || !Array.isArray(rawDataArray)) {
                    return ["0"];
                }

                const variables = rawDataArray.map(item => item.value?.value || "0");
                console.log("Fetched Variables:", variables);
                return variables;

            } catch (error) {
                const isTimeout = error.name === 'AbortError' || error.code === 'UND_ERR_CONNECT_TIMEOUT';
                if (isTimeout && i < retries - 1) {
                    console.warn(`Attempt ${i + 1} timed out. Retrying...`);
                    // Wait 1 second before retrying
                    await new Promise(res => setTimeout(res, 1000));
                    continue;
                }
                console.error("Failed to fetch variables:", error.message);
                return ["0"];
            }
        }
    }

    async function get_validators(arg) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
        method: 'POST',
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax8::return_state",
            type_arguments: [],
            arguments: ["0x270ed7309bf9bfccd6fdc03e0cc873925c79c30a8849127e44a85498d12d82e10a000000000000000e000000000000000000000000000000"]
        })
        });

        const body = await response.json();
        const validatorsData = body?.result?.[0]?.validators?.data || [];

        const validatorsArray = validatorsData.map(v => ({
            address: v.key,
            index: Number(v.value.index),
            pub_key: v.value.pub_key
        }));

        data.validators = validatorsArray;
        console.log("Validators:", validatorsArray);
        return validatorsArray;

    } catch (error) {
        console.error("Failed to fetch validators:", error);
        data.validators = [];
        return [];
    }
    }


async function computeValidatorRoot(pubkeys) {
    const poseidon = await buildPoseidon({ arity: 2 });

    const F = poseidon.F;

    // Copy leaves
    let valTree = [...pubkeys];

    // Build binary tree (64 leaves → 63 internal nodes)
    for (let i = 0; i < nValidators-1; i++) {
        const left = valTree[2 * i];
        const right = valTree[2 * i + 1];
        // Poseidon returns FieldElement, convert to BigInt
        valTree[nValidators + i] = F.toObject(poseidon([left, right]));
    }

    // Return root as BigInt
    return valTree[126];
}


async function calculateSigSummary() {
    const poseidon = await buildPoseidon({ arity: 2 });

    const F = poseidon.F;

    // Collect signed validator indices
    let signedIndices = data.validators.map(v => v.index);
    console.log("Signed indices:", signedIndices);

    // Create 64-bit BigInt bitmask
    let bitmask = 0n;
    signedIndices.forEach(index => {
        if (index >= 0 && index < nValidators) {
            bitmask |= (1n << BigInt(index));
        }
    });

    // Hash the bitmask with Poseidon
    const hash = poseidon([bitmask]);
    const sigSummaryBigInt = F.toObject(hash); // Convert FieldElement → BigInt

    // Return decimal string for Circom input
    return sigSummaryBigInt.toString();
}


function buildPayload(root, variable_id, value, epoch) {
    console.log("--- Starting buildPayload ---");
    
    // Serialization
    const rootBytes = root instanceof Buffer ? new Uint8Array(root) : root;
    const valueBytes = (typeof value === 'number' || typeof value === 'bigint' || typeof value === 'string') 
        ? BCS.bcsSerializeUint64(BigInt(value)) 
        : BCS.bcsToBytes(value);
    
    const variableIdBytes = BCS.bcsSerializeUint64(BigInt(variable_id));
    const epochBytes = BCS.bcsSerializeUint64(BigInt(epoch));
    
    const payload = new Uint8Array(rootBytes.length + variableIdBytes.length + valueBytes.length + epochBytes.length);
    let offset = 0;
    payload.set(rootBytes, offset); offset += rootBytes.length;
    payload.set(variableIdBytes, offset); offset += variableIdBytes.length;
    payload.set(valueBytes, offset); offset += valueBytes.length;
    payload.set(epochBytes, offset);

    const messageHex = '0x' + Array.from(payload).map(b => b.toString(16).padStart(2, '0')).join('');
    console.log("Generated Message Hex:", messageHex.substring(0, 20) + "...");
    
    // Store the hex in data
    data.messageHex = messageHex;
    data.message = payload;

    // HISTORY UPDATE
    if (!data.messageHistory) data.messageHistory = [];
    
    const lastEntry = data.messageHistory[data.messageHistory.length - 1];

    if (!lastEntry || lastEntry.hex !== messageHex) {
        console.log("Status: Unique Hex found. Pushing to history.");
        data.messageHistory.push({
            hex: messageHex,
            timestamp: new Date().toISOString()
        });
    } else {
        console.log("Status: Duplicate Hex detected. Skipping push.");
    }

    // Keep last 2
    while (data.messageHistory.length > 2) {
        data.messageHistory.shift();
    }

    // UPDATE POINTERS
    data.lastMessage = data.messageHistory[data.messageHistory.length - 1] || null;
    data.previousMessage = data.messageHistory[data.messageHistory.length - 2] || null;

    // SAVE TO DISK
    try {
        console.log("Attempting to write to file...");
        fs.writeFileSync(HISTORY_FILE, JSON.stringify({ messageHistory: data.messageHistory }, null, 2), 'utf8');
        console.log("✅ File updated successfully.");
    } catch (err) {
        console.error("❌ Write Error:", err.message);
    }

    return payload;
}
async function validate(variable_name, variable_id, newValue) {
    await initialize();
    try {
        const poseidon = await buildPoseidon({ arity: 2 });

        let variables = await get_allVariables();
        const tree = new PoseidonMerkleTree(variables, poseidon);
        const root = tree.getRoot(); 
        const epoch = 0;

        // Update global data object properly
        data.value = newValue;
        data.epoch = epoch;
        data.variable_id = variable_id;
        data.variable_name = variable_name;
        data.allVariables = variables;
        
        // Fetch validators using the PREVIOUS message hex from history
        //if (data.previousMessage?.hex) {
        //    data.validators = await get_validators(data.previousMessage.hex);
        //} else {
        //    data.validators = [];
        //}


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

        const senderAddr = senderAcc.address();

        
        const txPayload = [
            serialized_message,
            BCS.bcsSerializeUint64(variable_id),
            serialized_value, // The 32-byte u256
            BCS.bcsSerializeStr(variable_name),
            serialized_signature
        ];

        const rawTx = await supraClient.createSerializedRawTxObject(
            senderAddr,
            300,
            "6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1",
            "Qiarax8",
            "validate_and_vote",
            [], 
            txPayload
        );
        console.log(root.toString('hex'));
        // 5. Sign and Send
        //SupraClient.signSupraTransaction(senderAcc, rawTx);
        //let tx =await supraClient.sendTxUsingSerializedRawTransaction(senderAcc, rawTx);
        //console.log(data);
        //console.log(tx);
        //return tx

    } catch (error) {
        console.error("Validation failed:", error);
    }
}



async function generateInputJson() {
    const { validators, epoch, variable_id, value: newValue } = data;

    // Use the exact same Poseidon setup
    const poseidon = await buildPoseidon({ arity: 2 });
    const F = poseidon.F;
    const Fp = F.p;

    // ----------------------------------------------------
    // HELPER: Robust Little Endian to BigInt
    // ----------------------------------------------------
    const fromLE = (hexStr) => {
        // 1. Remove 0x prefix
        let clean = hexStr.startsWith('0x') ? hexStr.slice(2) : hexStr;
        // 2. Ensure even length for Buffer
        if (clean.length % 2 !== 0) clean = '0' + clean;
        // 3. Create Buffer, Reverse, convert to Hex
        const buf = Buffer.from(clean, 'hex');
        const reversedHex = buf.reverse().toString('hex');
        // 4. Return BigInt
        return BigInt('0x' + reversedHex);
    };

    // ----------------------------------------------------
    // 1. Validator pubkeys 
    // ----------------------------------------------------
    const validatorPubKeysList = Array.from({ length: 64 }, (_, i) => {
        const v = validators.find(x => x.index === i);
        if (!v) return 1n; 
        return BigInt(v.pub_key) % Fp;
    });

    // ----------------------------------------------------
    // 2. Build Tree & Debug Leaf Hash
    // ----------------------------------------------------
    const rawVariables = await get_allVariables();
    
    // Convert all raw variables using the robust fromLE
    const variables = rawVariables.map(hex => fromLE(hex));
    
    // Ensure the tree is built with BigInts
    const tree = new PoseidonMerkleTree(variables, poseidon);

    // DEBUG: Calculate the expected Leaf Hash in JS
    // In Circom: Poseidon(variableID, currentValue)
    const currentValBigInt = variables[variable_id] || 0n;
    const leafHashJS = F.toObject(poseidon([BigInt(variable_id), currentValBigInt]));
    
    console.log(`\n--- DEBUG LEAF HASH ---`);
    console.log(`Variable ID: ${variable_id}`);
    console.log(`Current Value: ${currentValBigInt}`);
    console.log(`Expected Leaf Hash: ${leafHashJS.toString()}`);
    // Check if tree leaf matches our expectation
    // Note: tree.leaves might differ slightly if your class structure handles leaves differently, 
    // but this check ensures the inputs to Circom are mathematically consistent.
    
    const { siblings, indices } = tree.generateProof(variable_id);

    // ----------------------------------------------------
    // 3. Calculate Roots
    // ----------------------------------------------------
    const validatorRoot = await computeValidatorRoot(validatorPubKeysList);
    const sigSummary = await calculateSigSummary();
    const rootBigInt = tree.getRoot();

    // ----------------------------------------------------
    // 4. Format Merkle Path
    // ----------------------------------------------------
    const TREE_DEPTH = 10;
    let pathElements = siblings.map(s => BigInt(s).toString());
    while (pathElements.length < TREE_DEPTH) pathElements.push("0");

    let pathIndices = indices.map(i => i.toString());
    while (pathIndices.length < TREE_DEPTH) pathIndices.push("0");

    // ----------------------------------------------------
    // 5. Construct Input
    // ----------------------------------------------------
    const input = {
        validatorRoot: validatorRoot.toString(),
        epoch: BigInt(epoch).toString(),
        variableID: BigInt(variable_id).toString(),
        newValue: BigInt(newValue).toString(),
        
        poseidonRoot: rootBigInt.toString(),
        currentValue: currentValBigInt.toString(),
        validatorPubKeys: validatorPubKeysList.map(x => x.toString()),
        sigSummary: BigInt(sigSummary).toString(),
        pathElements: pathElements,
        pathIndices: pathIndices
    };

    console.log("Input poseidonRoot:", input.poseidonRoot);
    
    return input;
}


async function main() {
    try {
        const { pA, pB, pC, publicSignals } = await prepareBatch();
        
        console.log("\n--- Proof from prepareBatch ---");
        console.log("pA:", pA);
        console.log("pB:", pB);
        console.log("pC:", pC);
        console.log("publicSignals:", publicSignals);
    } catch (err) {
        console.error("Error generating proof:", err);
    }
}

async function runWorkflow() {
  try {
    // STEP 1: Run validation first and WAIT for it to finish
    await get_validators();
    console.log("Starting Validation...");
    await validate("cxv", 10, 14);

    //console.log(data);
        console.log(data);
    // Make sure validators exist before generating JSON
    if (!data.validators || data.validators.length === 0) {
    console.log("❌ No validators found. Skipping JSON generation.");
    return;
    }


    // STEP 2: Generate the JSON
    console.log("Generating JSON...");

    const inputJsonObject = await generateInputJson(); // returns an object
    fs.writeFileSync("./input.json", JSON.stringify(inputJsonObject, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
    console.log("✅ input.json generated.");

    // STEP 3: Generate Proof and Command
    // await generateFullAptosTransaction();
    main();
  } catch (error) {
    console.error("Workflow failed:", error);
  }
}

// Start the sequence
runWorkflow();
