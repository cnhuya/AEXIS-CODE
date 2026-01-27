
const fs = require("fs");
const path = require("path");
const { buildPoseidon, buildEddsa } = require("circomlibjs");
const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { ethers } = require("ethers"); // Keccak256 is standard, or use crypto
const { PoseidonMerkleTree, signRotationMessage, generateGenesisRoot,get_validators } = require("../util/zk/zk_builders.js");
const { build_input } = require("../util/zk/input_builders.js");

const { prepareBatch } = require("../util/prover.js");
const { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, fetchSupraEvent } = require("../util/supra/supra_util.js");

const { sui_run } = require("../util/sui/sui_handle_zk.js");
const { evm_run } = require("../util/evm/evm_handle_zk.js");


let supraClient;


async function initialize() {
    supraClient = await SupraClient.init(
        "https://rpc-testnet.supra.com", // example URL
        { /* your config */ }
    );
    
    // Now you can call validate or other logic
    // await validate(id, value);
}

let data = {
    epoch: 1,
};

    async function deriveBabyJubKey(senderAcc) {
        //console.log(senderAcc);
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
        let babyPrivKey = Buffer.from(babyPrivKeyHex.slice(2), "hex");

        const pubKey = eddsa.prv2pub(babyPrivKey);
        return {
            privKey: babyPrivKey,
            pubKeyX: eddsa.F.toObject(pubKey[0]).toString(),
            pubKeyY: eddsa.F.toObject(pubKey[1]).toString(),
        }

    }


const BRIDGE_CONFIG = {
    // Keys from your comments
    privateKeyHexs: [
        "a5c37eb824028069f8ecad85133c77e6dbec32c52a9e809cff5d284c2e8526d2",
        "e25755f077b9184646e8882d1705a0235651b58402f5ebd94f5b2a2ad124efa5",
        "6cb168ab2ba30211d0b0e52b16acfe1a9438457088732f66079c6635f00bea50",
        //"76e4e301772698c31d08b42fd39551690c99b1c5689ed147c7ed4aa7f5f5eb6f"
    ],
    derivationMessage: "Sign to initialize your Bridge Validator Key. \n\nThis will not cost any gas.",
};


async function AllValidate(config, events) {
    // Using entries() gives us both the index (i) and the private key (pk)

    //let events = await fetchSupraEvent("0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::zkbalV1::TestEvent");
    // add database logic, i.e if new fetched events then execute code below for each one of them

for (const [i, pk] of config.privateKeyHexs.entries()) {
    try {
        const cleanPk = pk.replace("0x", "");
        const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
        
        const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);
        console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`);
        
        // Ensure validate() is awaited properly
        await validate();

        // Use for...of instead of forEach to respect 'await'
        for (const eventItem of array) {
            const { event_data } = eventItem; // Extract data from the formatted event object
            
            // 1. Recreate the Poseidon hash inputs as defined in Circom:
            // [oldAccountRoot, newAccountRoot, storageID, updatedBalance]
            const messageInputs = [
                eveevent_datant_data.oldAccountRoot, 
                event_data.newAccountRoot, 
                event_data.storageID, 
                event_data.balance
            ];

            // 2. Sign the message using the BabyJub private key
            // Note: signRotationMessage should internally use the same Poseidon(4) as the circuit
            let signature = await signRotationMessage(babyJubData.privKey, messageInputs);
            
            console.log(`Validator #${i + 1} signed event for StorageID: ${event_data.storageID}`);

            // 3. Prepare payload for Supra contract
            // Note: Ensure the payload order matches your Move contract's 'validate' function
            const payload3 = [
                data.epoch, 
                data.oldAccountRoot, 
                data.newAccountRoot,
                signature.r8x, 
                signature.r8y, 
                signature.s, 
                signature.message
            ];

            const client = await getSupraClient("https://rpc-testnet.supra.com");
            await SupraSendTransaction(client, senderAcc, payload3, "validate");
        }

    } catch (error) {
        console.error(`Error processing key at index ${i}:`, error);
    }
}
}


function startPolling(intervalMs = 5000) {
    // Create a named function so we can call it recursively
    const run = async () => {
        console.log("Fetching Epoch...");
        let new_events = await fetchSupraEvent("test");

        if (data.events !== new_events) {
            console.log("ℹ️ New events:", new_events);
            data.events = new_events;
            console.log("Fetching Validators...");
            data.validators = await get_validators();
            console.log("Starting Validation...");
            await AllValidate(BRIDGE_CONFIG);
            console.log("Fetching Signatures...");
            await get_validators_type_signatures(epoch);
            console.log("Building Input...");
            await build_input(data, "balances");
            console.log("Preparing Proof...");
            let result = await prepareBatch();
            if(result){
                console.log("✅ Proof Prepared:", result);
            };
            console.log("Evm ZK Run...");
            await evm_run();
            console.log("Sui ZK Run...");
            await sui_run();
        };
        setTimeout(run, intervalMs);
    };

    // Return the result of the first call so the workflow can wait for it
    return run(); 
}

async function get_validators_type_signatures(type, message) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::Qiarax39::return_type_state",
                type_arguments: [],
                arguments: [type, message]
            })
        });

       // console.log("Checking for epoch:", epoch);
        const body = await response.json();
       // console.log(body);
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
        // Ensure global/outer 'data' object is updated if it exists
        if (typeof data !== 'undefined' && data.validators_sig != validatorsArray) {
            data.validators_sig = validatorsArray;
        }

        return validatorsArray;

    } catch (error) {
        // Suppress logging if you want it completely silent, or keep as a minor trace
        if (typeof data !== 'undefined') {
            data.validators_sig = [];
        }
        console.log("🚨 Validator Signatures Fetch error:", error);
        return [];
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
        

    } catch (error) {
        console.error("Validation failed:", error);
    }
}

async function runWorkflow() {
  try {
;
    // STEP 1: Fetch Validators
    console.log("Periodically Fetching Validators Have Been Started...");
    await startPolling();
    await registerAllValidators(BRIDGE_CONFIG);
    console.log(data);

  } catch (error) {
    console.error("Workflow failed:", error);
  }
}

// Start the sequence
runWorkflow();