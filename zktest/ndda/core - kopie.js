const Fastify = require('fastify');
const snarkjs = require("snarkjs");
const fs = require("fs");
const { buildPoseidon, buildEddsa } = require("circomlibjs");
const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { poseidon } = require("poseidon-lite");
const { ethers } = require("ethers"); // Keccak256 is standard, or use crypto
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

let data = {
    epoch: 0,
};


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
        this.leaves = fullLeaves.map((v, i) => {
            // If it's a dummy leaf (padding), we use zeros
            if (v === "0") {
                return F.toObject(this.poseidon([0, 0, 0]));
            }
            // MUST match Circom leafHasher: Poseidon(pubKeyX, pubKeyY, stake)
            return F.toObject(this.poseidon([
                BigInt(v.pub_key_x), 
                BigInt(v.pub_key_y), 
                BigInt(v.staked)
            ]));
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

const BRIDGE_CONFIG = {
    // Keys from your comments
    privateKeyHexs: [
        "e25755f077b9184646e8882d1705a0235651b58402f5ebd94f5b2a2ad124efa5",
        "a5c37eb824028069f8ecad85133c77e6dbec32c52a9e809cff5d284c2e8526d2",
        "6cb168ab2ba30211d0b0e52b16acfe1a9438457088732f66079c6635f00bea50",
        "76e4e301772698c31d08b42fd39551690c99b1c5689ed147c7ed4aa7f5f5eb6f"
    ],
    derivationMessage: "Sign to initialize your Bridge Validator Key. \n\nThis will not cost any gas.",
};


async function initializeAllValidators(config) {
    return await Promise.all(config.privateKeyHexs.map(async (pk) => {
        // Initialize the Supra Account
        const cleanPk = pk.replace("0x", "");
        const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
        
        // Utilize the derivation function
        const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);
        
        return {
            supraAddress: senderAcc.getAddress(),
            babyJub: babyJubData
        };
    }));
}


    async function deriveBabyJubKey(senderAcc) {
        console.log(senderAcc);
        const eddsa = await buildEddsa();

        // 2. The "Seed" Message
        const message = "Sign to initialize your Bridge Validator Key. \n\nThis will not cost any gas.";
        
        // 3. Convert message to Buffer for Supra's signBuffer
        const msgBuffer = Buffer.from(message);

        // 4. Get the ECDSA/EdDSA signature from the Supra Account
        // This signature is deterministic for the given msgBuffer
        const signature = await senderAcc.signBuffer(msgBuffer); 
        
        // 5. Hash the signature to get a 32-byte private key
        // Most ZK projects use Keccak256 or SHA256. 
        // If Supra SDK doesn't have a direct 'hash' util, ethers.keccak256 is fine.
        const sigBytes = signature.signedBytes ? signature.signedBytes : signature;
        const babyPrivKeyHex = ethers.keccak256(sigBytes.toString('hex')).slice(2);
        
        // 6. Convert hex string to Buffer for BabyJubJub
        babyPrivKey = Buffer.from(babyPrivKeyHex.slice(2), "hex");

        const pubKey = eddsa.prv2pub(babyPrivKey);
        return {
            privKey: babyPrivKeyHex,
            pubKeyX: eddsa.F.toObject(pubKey[0]).toString(),
            pubKeyY: eddsa.F.toObject(pubKey[1]).toString(),
        }

    }


async function get_validators() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::QiaraVv17::return_all_active_parents_full",
                type_arguments: [],
                arguments: []
            })
        });

        const body = await response.json();
        const validatorsData = body.result?.[0].data;

        if (!validatorsData) return data.validators || [];

        const validatorsArray = validatorsData.map(v => {
            // Safer addition: ensure both values exist as numbers/strings before adding
            let total_staked = (Number(v.value.self_staked) || 0) + (Number(v.value.total_stake) || 0);

            return {
                address: v.key,
                staked: BigInt(total_staked).toString(), 
                pub_key_x: v.value.pub_key_x,
                pub_key_y: v.value.pub_key_y,
            };
        });

        // FIXED: Compare the actual content of the arrays
        if (JSON.stringify(validatorsArray) === JSON.stringify(data.validators)) {
            // Data hasn't changed; skip the update
            return data.validators;
        }

        console.log("New Validators Detected!");
        data.validators = validatorsArray;
        console.log("Validators:", validatorsArray);
        return validatorsArray;

    } catch (error) {
        console.error("Failed to fetch validators:", error);
        // Better to keep existing data on error rather than clearing it
        return data.validators || [];
    }
}

function startPolling(intervalMs = 500000) {
    // Create a named function so we can call it recursively
    const run = async () => {
        console.log("Fetching Validators...");
        await get_validators();
        console.log("Validating...");
        await validate();
        console.log("Fetching Signatures...");
        await get_validators_signatures(data.currentRoot);
        console.log("Trying to Prove...");
        await main();
        setTimeout(run, intervalMs);
    };

    // Return the result of the first call so the workflow can wait for it
    return run(); 
}

async function get_validators_signatures(old_root) {
    //console.log(old_root);
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax24::return_state",
                type_arguments: [],
                arguments: [old_root.toString()]
            })
        });

        const body = await response.json();
        // 1. Handle explicit RPC errors
        if (body.error) {
            return []; 
        }
        // 2. Safely access the data and provide a fallback empty array
        const validatorsData = body.result?.[0]?.parents?.data;
        // 3. Return empty early if no data exists to prevent .map() from crashing
        if (!validatorsData || !Array.isArray(validatorsData)) {
            return [];
        }
        const validatorsArray = validatorsData.map(v => {
            return {
                address: v.key,
                staked: BigInt(v.value.staked || 0).toString(), 
                pub_key_x: v.value.pub_key_x,
                pub_key_y: v.value.pub_key_y,
                s: v.value.s,
                s_r8x: v.value.s_r8x,
                s_r8y: v.value.s_r8y,
                index: v.value.index
            };
        });
        // Ensure global/outer 'data' object is updated if it exists
        if (typeof data !== 'undefined' && data.validators_sig != validatorsArray) {
            data.validators_sig = validatorsArray;
            await build_input();
        }

        return validatorsArray;

    } catch (error) {
        // Suppress logging if you want it completely silent, or keep as a minor trace
        if (typeof data !== 'undefined') {
            data.validators_sig = [];
        }
        return [];
    }
}

async function generateGenesisRoot(validators) {
    const poseidon = await buildPoseidon();
    // 1. Calculate leaves
    const leaves = validators.map(val => {
        // Ensure values are BigInts or strings
        return poseidon([val.pub_key_x, val.pub_key_y, val.staked]);
    });

    // 2. Pad leaves to the nearest power of 2 (e.g., 32 for depth 5)
    const nValidators = 8;
    while (leaves.length < nValidators) {
        // Use 0 as the "empty leaf" value
        leaves.push(poseidon.F.e("0"));
    }

    // 3. Build the Merkle Tree
    let currentLevel = leaves;
    while (currentLevel.length > 1) {
        let nextLevel = [];
        for (let i = 0; i < currentLevel.length; i += 2) {
            nextLevel.push(poseidon([currentLevel[i], currentLevel[i+1]]));
        }
        currentLevel = nextLevel;
    }

    const root = poseidon.F.toObject(currentLevel[0]).toString();
    //console.log("Genesis Validator Root:", root);
    return root;
}

async function signRotationMessage(babyPrivKey, currentValidatorRoot, newValidatorRoot, epoch) {
    console.log(babyPrivKey);
    console.log(currentValidatorRoot);
    console.log(newValidatorRoot);
    console.log(epoch);
    const eddsa = await buildEddsa();
    const poseidon = await buildPoseidon();

    // 1. Prepare the Message Hash
    // This MUST match the msgHasher = Poseidon(3) in your ValidatorRotation circuit:
    // [currentValidatorRoot, newValidatorRoot, epoch]
    const msgHash = poseidon([
        currentValidatorRoot, 
        newValidatorRoot, 
        epoch
    ]);

    // 2. Sign the message
    const signature = eddsa.signPoseidon(babyPrivKey, msgHash);
    
    return {
        message: poseidon.F.toObject(msgHash).toString(),
        r8x: eddsa.F.toObject(signature.R8[0]).toString(),
        r8y: eddsa.F.toObject(signature.R8[1]).toString(),
        s: signature.S.toString(),
        isSigned: 1
    };
}

async function build_input() {
    try {
        const CIRCUIT_N_VALIDATORS = 8;
        
        // Check if tree exists before using it
        if (!data.tree) {
            console.error("Tree not initialized. Skipping input build.");
            return;
        }

        const inputs = {
            currentValidatorRoot: data.currentRoot.toString(),
            newValidatorRoot: data.newValidatorRoot.toString(),
            epoch: "0",
            threshold: "2",
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

        const sigMap = {};
        if (data.validators_sig) {
            data.validators_sig.forEach(sig => {
                sigMap[Number(sig.index)] = sig;
            });
        }

        for (let i = 0; i < CIRCUIT_N_VALIDATORS; i++) {
            // FIX: Reference data.tree here
            const proof = data.tree.generateProof(i); 
            inputs.valPathElements.push(proof.siblings.map(s => s.toString()));
            inputs.valPathIndices.push(proof.indices.map(idx => idx.toString()));

            const sig = sigMap[i];
            const v = data.validators[i];

            if (sig && v) {
                inputs.isSigned.push(1);
                inputs.validatorPubKeysX.push(v.pub_key_x.toString());
                inputs.validatorPubKeysY.push(v.pub_key_y.toString());
                inputs.validatorStakes.push(v.staked.toString());
                inputs.signaturesR8x.push(sig.s_r8x.toString());
                inputs.signaturesR8y.push(sig.s_r8y.toString());
                inputs.signaturesS.push(sig.s.toString());
            } else {
                // Defaulting to 0 for non-signers or empty slots
                inputs.isSigned.push(0);
                inputs.validatorPubKeysX.push(v ? v.pub_key_x.toString() : "0");
                inputs.validatorPubKeysY.push(v ? v.pub_key_y.toString() : "0");
                inputs.validatorStakes.push(v ? v.staked.toString() : "0");
                inputs.signaturesR8x.push("0");
                inputs.signaturesR8y.push("0");
                inputs.signaturesS.push("0");
            }
        }

        const fs = require('fs');
        fs.writeFileSync("./input.json", JSON.stringify(inputs, null, 2));
        console.log("✅ input.json ready");
        
    } catch (error) {
        console.error("Failed to build circuit input:", error);
    }
}

async function validate() {
    await initialize();
    try {

        let newValidatorRoot = await generateGenesisRoot(data.validators);
        
        
            console.log("New Validator Root:", newValidatorRoot);
            data.newValidatorRoot = newValidatorRoot;

            const poseidon = await buildPoseidon();
            const CIRCUIT_N_VALIDATORS = 8; 
            const CIRCUIT_TREE_DEPTH = 4;   

            // 1. Build the Tree
            const validatorsForTree = data.validators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
                pub_key_x: BigInt(v.pub_key_x),
                pub_key_y: BigInt(v.pub_key_y),
                staked: BigInt(v.staked)
            }));
            const tree = new PoseidonMerkleTree(validatorsForTree, poseidon, CIRCUIT_TREE_DEPTH);
            data.tree = tree;
            const currentRoot = tree.getRoot(); 
            data.currentRoot = currentRoot;

            // Sign the rotation message
            let signature = await signRotationMessage(babyPrivKey, data.currentRoot, data.newValidatorRoot, 0);

            // 3. Transaction Payload (Using your WORKING manual serialization pattern)
            // We convert everything to U8 Vectors just like your working 'validate_and_vote'
            const txPayload = [
                serializeU8Vector(Array.from(Buffer.from(data.currentRoot.toString()))),
                serializeU8Vector(Array.from(Buffer.from(signature.r8x.toString()))),
                serializeU8Vector(Array.from(Buffer.from(signature.r8y.toString()))),
                serializeU8Vector(Array.from(Buffer.from(signature.s.toString()))),
                serializeU8Vector(Array.from(Buffer.from(signature.message.toString()))),
            ];

            // 4. Create Transaction Object
            const senderAddr = senderAcc.address();
            const accountInfo = await supraClient.getAccountInfo(senderAddr);
            const rawTx = await supraClient.createSerializedRawTxObject(
                senderAddr,
                accountInfo.sequence_number, // nonce
                "6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1",
                "Qiarax24",
                "validate", // Your Move function name
                [], 
                txPayload
            );
            
            // 5. Send Transaction
            const txHash = await supraClient.sendTxUsingSerializedRawTransaction(senderAcc, rawTx);
            console.log("🚀 Transaction Successful! Hash:", txHash);
            return txHash;
        

    } catch (error) {
        console.error("Validation failed:", error);
    }
}

async function buildMoveFunction(proofData) {
    const { proofAMove, proofBMove, proofCMove } = await formatProofForMove(proofData);
    
    // Remove '0x' from the results for the CLI 'hex:' format
    const cleanA = proofAMove.replace('0x', '');
    const cleanB = proofBMove.replace('0x', '');
    const cleanC = proofCMove.replace('0x', '');

    const baseString = "supra move tool run --function-id 0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::bridge_coreV7::verify_with_hardcoded_vk2 --args";

    // Re-applying your formatting: hex:"STRING" and u256:[VALS]
    const args = [
        `hex:"${cleanA}"`, 
        `hex:"${cleanB}"`, 
        `hex:"${cleanC}"`, 
        `"u256:[${proofData.publicSignals.join(',')}]"`
    ];

    const fullString = `${baseString} ${args.join(' ')}`;
    console.log(fullString);
    return fullString;
}

async function main() {
    try {
        const result = await prepareBatch();
        
        console.log("\n--- Proof from prepareBatch ---");
        console.log("pA:", result.pA);
        console.log("pB:", result.pB);
        console.log("pC:", result.pC);
        console.log("publicSignals:", result.publicSignals);

        data.result = result;
    } catch (err) {
        console.error("Error generating proof:", err);
    }
}

function to32Bytes(input) {
    let bigIntValue;
    if (typeof input === 'bigint') {
        bigIntValue = input;
    } else if (typeof input === 'string') {
        bigIntValue = input.startsWith('0x') ? BigInt(input) : BigInt(input);
    } else if (Buffer.isBuffer(input)) {
        bigIntValue = BigInt('0x' + input.toString('hex'));
    } else {
        bigIntValue = BigInt(input);
    }

    let hex = bigIntValue.toString(16).padStart(64, '0');
    if (hex.length > 64) hex = hex.slice(-64);

    const buf = Buffer.from(hex, 'hex');
    return Uint8Array.from(buf.reverse()); // Little Endian
}

const formatG1 = (point) => {
    const x = to32Bytes(point[0]);
    const y = to32Bytes(point[1]);
    const buffer = Buffer.concat([Buffer.from(x), Buffer.from(y)]);
    if (buffer.length !== 64) throw new Error(`Invalid G1 length: ${buffer.length}`);
    return buffer.toString('hex');
};

async function extractMoveVK() {
    
    await formatProofForMove(data.result);
    const vk = JSON.parse(fs.readFileSync("./zk/validators/verification_key.json"));

    // Your existing requirement: 32 bytes + Little Endian

    const formatG2 = (point) => {
        // Concatenation order: X Real, X Imaginary, Y Real, Y Imaginary
        const x_real = to32Bytes(point[0][0]);
        const x_imag = to32Bytes(point[0][1]);
        const y_real = to32Bytes(point[1][0]);
        const y_imag = to32Bytes(point[1][1]);
        const buffer = Buffer.concat([
            Buffer.from(x_real), 
            Buffer.from(x_imag), 
            Buffer.from(y_real), 
            Buffer.from(y_imag)
        ]);

        // VALIDATION: G2 must be exactly 128 bytes
        if (buffer.length !== 128) throw new Error(`Invalid G2 length: ${buffer.length}`);
        return buffer.toString('hex');
    };

    const results = {
        vk_alpha_g1: formatG1(vk.vk_alpha_1),
        vk_beta_g2: formatG2(vk.vk_beta_2),
        vk_gamma_g2: formatG2(vk.vk_gamma_2),
        vk_delta_g2: formatG2(vk.vk_delta_2),
        vk_uvw_gamma_g1: vk.IC.map(point => formatG1(point))
    };

    // --- FINAL FORMAT CHECK ---
    console.log("🔍 Checking Format Integrity...");
    const checks = [
        { name: "Alpha G1", len: results.vk_alpha_g1.length, target: 128 }, // 128 hex chars = 64 bytes
        { name: "Beta G2",  len: results.vk_beta_g2.length,  target: 256 }, // 256 hex chars = 128 bytes
        { name: "Gamma G2", len: results.vk_gamma_g2.length, target: 256 },
        { name: "Delta G2", len: results.vk_delta_g2.length, target: 256 },
    ];

    checks.forEach(c => {
        if (c.len === c.target) {
            console.log(`✅ ${c.name}: Correct (${c.len} hex chars)`);
        } else {
            console.error(`❌ ${c.name}: ERROR! Expected ${c.target} chars, got ${c.len}`);
        }
    });

    // IC length check based on nPublic (nPublic + 1)
    if (results.vk_uvw_gamma_g1.length === vk.nPublic + 1) {
        console.log(`✅ IC Vector: Correct length (${results.vk_uvw_gamma_g1.length} points)`);
    }

    console.log("\n--- READY FOR MOVE ---");
    console.log(`const VK_ALPHA_G1: vector<u8> = x"${results.vk_alpha_g1}";`);
    console.log(`const VK_BETA_G2: vector<u8> = x"${results.vk_beta_g2}";`);
    console.log(`const VK_GAMMA_G2: vector<u8> = x"${results.vk_gamma_g2}";`);
    console.log(`const VK_DELTA_G2: vector<u8> = x"${results.vk_delta_g2}";`);
    // results.vk_uvw_gamma_g1 is an array of formatted G1 hex strings
    const icPointsMove = results.vk_uvw_gamma_g1
        .map(hex => `        x"${hex}"`)
        .join(',\n');

    console.log("\n--- MOVE VECTOR FORMAT ---");
    console.log(`const VK_IC_POINTS: vector<vector<u8>> = vector[\n${icPointsMove}\n    ];`);
    return results;
}

async function formatProofForMove(proofData) {
    const { pA, pB, pC, publicSignals } = proofData;

    // 1. Format Public Inputs (Scalar Field Elements - 32 bytes each)
    // S is a plain field element, so we just use to32Bytes on each.
    const publicInputsMove = publicSignals.map(sig => {
        return "0x" + Buffer.from(to32Bytes(sig)).toString('hex');
    });

    // 2. Format Proof A (G1 - 64 bytes)
    const proofAMove = "0x" + formatG1(pA);

    // 3. Format Proof B (G2 - 128 bytes)
    // NOTE: Your prepareBatch already ordered pB as [XReal, XImag, YReal, YImag]
    // So we just apply to32Bytes to each element in that specific order.
    const pB_raw = Buffer.concat([
        Buffer.from(to32Bytes(pB[0])), // X Real
        Buffer.from(to32Bytes(pB[1])), // X Imag
        Buffer.from(to32Bytes(pB[2])), // Y Real
        Buffer.from(to32Bytes(pB[3]))  // Y Imag
    ]);
    const proofBMove = "0x" + pB_raw.toString('hex');

    // 4. Format Proof C (G1 - 64 bytes)
    const proofCMove = "0x" + formatG1(pC);

    console.log("\n--- PROOF DATA FOR MOVE ---");
    console.log(`Proof A (G1): ${proofAMove}`);
    console.log(`Proof B (G2): ${proofBMove}`);
    console.log(`Proof C (G1): ${proofCMove}`);
    console.log(`Public Inputs (S): [${publicInputsMove.join(', ')}]`);

    return {
        publicInputsMove,
        proofAMove,
        proofBMove,
        proofCMove
    };
}

async function runWorkflow() {
  try {

    // STEP 0: Generate BabyJubJub Key
    if(babyPrivKey == null){
        console.log("Deriving BabyJubJub Key...");
        console.log("Keys: ", await deriveBabyJubKey(senderAcc));
    };

    // STEP 1: Fetch Validators
    console.log("Periodically Fetching Validators Have Been Started...");
    await startPolling();

    //console.log(data);
    await extractMoveVK();
    await buildMoveFunction(data.result);
    // STEP 3: Generate Proof and Command
    // await generateFullAptosTransaction();
    //main();
  } catch (error) {
    console.error("Workflow failed:", error);
  }
}

// Start the sequence
runWorkflow();