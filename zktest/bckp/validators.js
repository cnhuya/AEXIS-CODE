
const fs = require("fs");
const path = require("path");
const { buildPoseidon, buildEddsa } = require("circomlibjs");
const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");

const { PoseidonMerkleTree, signRotationMessage, generateGenesisRoot, deriveBabyJubKey } = require("../util/zk/zk_builders.js");
const { build_input } = require("../util/zk/input_builders.js");

const { prepareBatch } = require("../util/prover.js");
const { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, getSupraAddress } = require("../util/supra/supra_util.js");

const { sui_run } = require("../util/sui/sui_handle_zk.js");
const { evm_run } = require("../util/evm/evm_handle_zk.js");

const { getSuiAccFromPrivKey, SuiSign, getSuiClient } = require("../util/sui/sui_util.js");
const { getPrivKey } = require("../util/global_util.js");
const { updateState, getState } = require('../util/state.js');
const { getEvmAccFromPrivKey, EvmSign } = require("../util/evm/evm_util.js");
const { config } = require("dotenv");
const { get } = require("http");
const { bcs } = require("@mysten/sui/bcs");
const { getegid } = require("process");

let supraClient;



//#region == GLOBALS === //
async function get_validators() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                //0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraVv12::return_all_active_parents_full
                function: "0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraValidatorsV11::return_all_active_validators_full",
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
                staked: BigInt(total_staked).toString(), 
                pub_key_x: v.value.pub_key_x,
                pub_key_y: v.value.pub_key_y,
            };
        });

        //console.log("Validators:", validatorsArray);
        return validatorsArray;

    } catch (error) {
        console.error("🚨 Failed to fetch validators:", error);
        // Better to keep existing data on error rather than clearing it
        return [];
    }
}
async function get_epoch() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraGenesisV11::return_epoch",
                type_arguments: [],
                arguments: []
            })
        });

        const body = await response.json();

        return Number(body.result);

    } catch (error) {
        console.error("🚨 Failed to fetch epoch:", error);
    }
}
async function get_validators_signatures(epoch) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::Qiarax12::return_state",
                type_arguments: [],
                arguments: [epoch.toString()]
            })
        });

       console.log("Checking for epoch:", epoch);
        const body = await response.json();
       console.log(body);
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
                message: v.value.message,
                s: v.value.s,
                s_r8x: v.value.s_r8x,
                s_r8y: v.value.s_r8y,
                index: v.value.index
            };
        });
        console.log(validatorsArray);
        updateState('validators', { sigs: validatorsArray });

        return validatorsArray;

    } catch (error) {
        // Suppress logging if you want it completely silent, or keep as a minor trace
        console.log("🚨 Validator Signatures Fetch error:", error);
        return [];
    }
}
//#endregion

async function initialize() {
    supraClient = await SupraClient.init(
        "https://rpc-testnet.supra.com", // example URL
        { /* your config */ }
    );
    
    // Now you can call validate or other logic
    // await validate(id, value);
}

const BRIDGE_CONFIG = {
    // Keys from your comments
    privateKeyHexs: [
       // "a5c37eb824028069f8ecad85133c77e6dbec32c52a9e809cff5d284c2e8526d2",
       "76e4e301772698c31d08b42fd39551690c99b1c5689ed147c7ed4aa7f5f5eb6f",
        "e25755f077b9184646e8882d1705a0235651b58402f5ebd94f5b2a2ad124efa5",
        "6cb168ab2ba30211d0b0e52b16acfe1a9438457088732f66079c6635f00bea50",
        
    ],
    derivationMessage: "Sign to initialize your Bridge Validator Key. \n\nThis will not cost any gas.",
};


async function registerAllValidators(config) {
    // Define your specific stake amounts in order
    const stakes = [10000, 100000, 444447];
    // Using entries() gives us both the index (i) and the private key (pk)
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {
            const cleanPk = pk.replace("0x", "");
            const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
            
            const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);
            console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`);
            
            //await validate();

            // Use the index 'i' to pick the stake from our array
            // If there are more than 3 keys, it defaults to 471
            const currentStake = stakes[i] !== undefined ? stakes[i] : 471;

            const isValidator = await checkValidator(senderAcc.address());
            
            if (!isValidator) {
                // Task 1: Save Validator with dynamic stake
                const payload1 = [senderAcc.address(), senderAcc.address(), currentStake];
                console.log(`Registering with stake: ${currentStake}`);
                
                await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload1, "save_validator");

                // Task 2: Register Parent
                let pubkeyX = babyJubData.pubKeyX;
                let pubkeyY = babyJubData.pubKeyY;
                const payload2 = [senderAcc.address(), pubkeyX, pubkeyY];
                await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload2, "register_parent");
            }
            console.log(`Validator #${i + 1}: ${senderAcc.address()} is already registered.`);
            // Task 3: Sign and Validate
            //let signature = await signRotationMessage(babyJubData.privKey, [data.currentRoot, data.newValidatorRoot, data.epoch]);
            //console.log(signature);
            //const payload3 = [data.epoch, "validators", data.currentRoot, signature.r8x, signature.r8y, signature.s, signature.message, []];
            //await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload3, "validate");
            

        } catch (error) {
            console.error(`Error processing key at index ${i}:`, error);
        }
    }
}

async function AllValidate(config) {
    // Using entries() gives us both the index (i) and the private key (pk)
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {
            const cleanPk = pk.replace("0x", "");
            const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
            
            const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);
            console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`);
            
            await validate();

            let data = getState('validators');
            console.log(data);

            // Task 3: Sign and Validate
            let signature = await signRotationMessage(babyJubData.privKey, [data.currentRoot, data.newRoot, data.epoch]);
            console.log(signature);
            const payload3 = [data.epoch, data.currentRoot, signature.r8x, signature.r8y, signature.s, signature.message];
            await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload3, "validate_state");

        } catch (error) {
            console.error(`Error processing key at index ${i}:`, error);
        }
    }
}


async function checkValidator(address) {
    console.log("Checking validator:", address);
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraVv12::return_parent",
                type_arguments: [],
                arguments: [address.toString("hex")]
            })
        });

        const body = await response.json();

        if(body.message){
            console.log("ℹ️ Validator not found.");
            return false;
        } else {
            return true;
        };

    } catch (error) {
        console.error("🚨 Failed to fetch validator:", error);
    }
}


function startPolling(intervalMs = 5000) {
    // Create a named function so we can call it recursively
    const run = async () => {
        console.log("Fetching Epoch...");
        let epoch = await get_epoch();
        let currentState = getState('validators');
        if (currentState.epoch !== epoch) {
            console.log("ℹ️ New epoch:", epoch);
            updateState('validators', { epoch: epoch });
            console.log("Fetching Validators...");
            updateState('validators', { validators: await get_validators() });
            console.log("Starting Validation...");
            await AllValidate(BRIDGE_CONFIG);
            console.log("Fetching Signatures...");
            await get_validators_signatures(epoch);
            console.log("Building Input...");
            await build_input("validators");
            console.log("Preparing Proof...");
            let result = await prepareBatch("validators");
            if(result){
                console.log("✅ Proof Prepared:", result);
            };
            console.log("Evm ZK Run...");
            await evm_run("validators", "sendZKP");
            console.log("Sui ZK Run...");
            await sui_run("validators", "sendZKP");
        };
        setTimeout(run, intervalMs);
    };

    // Return the result of the first call so the workflow can wait for it
    return run(); 
}


async function validate() {
    await initialize();
    try {

            let data = getState('validators');
            let newValidatorRoot = await generateGenesisRoot(data.validators);
        
            console.log("New Validator Root:", newValidatorRoot);
            updateState('validators', { newRoot: newValidatorRoot });

            const poseidon = await buildPoseidon();
            const CIRCUIT_N_VALIDATORS = 16; 
            const CIRCUIT_TREE_DEPTH = 4;   

            // 1. Build the Tree
            const validatorsForTree = data.validators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
                pub_key_x: BigInt(v.pub_key_x),
                pub_key_y: BigInt(v.pub_key_y),
                staked: BigInt(v.staked)
            }));
            const tree = new PoseidonMerkleTree(validatorsForTree, poseidon, CIRCUIT_TREE_DEPTH, "validators");
            updateState('validators', { tree: tree });
            const currentRoot = tree.getRoot(); 
            updateState('validators', { currentRoot: currentRoot });
        

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

    await registerAllValidators(BRIDGE_CONFIG);
    // STEP 1: Fetch Validators
    console.log("Periodically Fetching Validators Have Been Started...");
    await startPolling();
    //await extractMoveVK();
    //await buildMoveFunction(data.result);
    // STEP 3: Generate Proof and Command
    // await generateFullAptosTransaction();
  } catch (error) {
    console.error("Workflow failed:", error);
  }
}

// Start the sequence
runWorkflow();

module.exports = { get_epoch, get_validators_signatures, get_validators };