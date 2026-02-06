const { buildPoseidon, buildEddsa } = require("circomlibjs");
const { HexString, SupraAccount, SupraClient, BCS } = require("supra-l1-sdk");
const { PoseidonMerkleTree, signRotationMessage, generateGenesisRoot, deriveBabyJubKey, generateGenericRoot } = require("../util/zk/zk_builders.js");
const { build_input } = require("../util/zk/input_builders.js");

const { prepareBatch } = require("../util/prover.js");
const { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, fetchSupraEvent } = require("../util/supra/supra_util.js");
const { updateState, getState } = require('../util/state.js');
const { strToField, convertLittleEndian,leHexToBI } = require('../util/global_util.js');
const { sui_run } = require("../util/sui/sui_handle_zk.js");
const { evm_run } = require("../util/evm/evm_handle_zk.js");

const { get_epoch, get_validators, get_validators_signatures } = require("./validators.js");

//let supraClient = await SupraClient.init("https://rpc-testnet.supra.com",);
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

async function get_all_variables() {

    let all = [];

    try {
        const headers_response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraStorageV1::viewHeaders",
                type_arguments: [],
                arguments: []
            })
        });

        const headers_body = await headers_response.json();
        console.log("Fetched all variable headers from QiaraStorageV2", headers_body);


        for (const header of headers_body.result[0]) {
            //console.log("Fetching variables for header:", header);
            
            const variables_response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
                method: 'POST',
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    function: "0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraStorageV1::viewConstants",
                    type_arguments: [],
                    arguments: [header]
                })
            });
            const variables_body = await variables_response.json();
            //console.log(`Results for ${header}:`, JSON.stringify(variables_body.result, null, 2));
            // Result format: [ "QiaraTiers", [var1, var2] ]
            all.push([ header, variables_body.result[0] ]);
        }

        return all

    } catch (error) {
        console.log("🚨 Fetch error:", error);
        return [];
    }
}

async function dataToVariable(data) {
    const resolvedData = await Promise.all(data);

    // Helper to decode Hex -> UTF8 String -> BigInt String
    const hexStringToBigIntString = (hex) => {
        if (!hex || hex === '0x') return "0";
        const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
        // 1. Convert hex bytes to a readable string (e.g., '0x30' -> '0')
        const decodedString = Buffer.from(cleanHex, 'hex').toString('utf8');
        // 2. Parse that string as a BigInt to ensure it's a valid number
        try {
            return BigInt(decodedString).toString();
        } catch (e) {
            console.error(`Failed to parse ${decodedString} as BigInt`, e);
            return "0";
        }
    };
    const pathElements = resolvedData.slice(6, 22).map(h => hexStringToBigIntString(h));
    return {
        // Text conversion (Header and Name stay as strings)
        oldRoot: hexStringToBigIntString(resolvedData[0]),
        newRoot: hexStringToBigIntString(resolvedData[1]),
        header: Buffer.from(resolvedData[2].replace('0x', ''), 'hex').toString('utf8'),
        name: Buffer.from(resolvedData[3].replace('0x', ''), 'hex').toString('utf8'),
        
        // Numeric conversion (Parse the string value inside the hex)
        newData: hexStringToBigIntString(resolvedData[4]),
        index: hexStringToBigIntString(resolvedData[5]),
        storedPath: pathElements // Save this!
    };
}

async function detect_variable_changes(oldVariables, newVariables) {
    const changes = [];

    // 1. Create a lookup map for the old data for fast access
    // Map structure: { "QiaraTokens": { "TRANSFER_FEE": "0x32..." } }
    const oldMap = new Map();
    for (const [header, constants] of oldVariables) {
        const constantMap = new Map();
        for (const c of constants) {
            constantMap.set(c.name, c.value.data);
        }
        oldMap.set(header, constantMap);
    }

    // 2. Iterate through new variables to find differences
    for (const [header, constants] of newVariables) {
        const oldConstants = oldMap.get(header);
        
        for (const current of constants) {
            const oldValue = oldConstants ? oldConstants.get(current.name) : undefined;
            const newValue = current.value.data;

            // 3. Detect change (or new variable addition)
            if (oldValue !== newValue) {
                changes.push({
                    header: header,
                    name: current.name,
                    newData: newValue,
                    index: current.index
                });
            }
        }
    }

    return changes;
}

async function AllValidate(config, eventItem) {
    const poseidon = await buildPoseidon();

    const zkState = await getState('variables');
    const tree = zkState.varTree; 
    const { oldRoot, newRoot } = await prepareRootsForWitness(tree, eventItem, poseidon);
    // 1. Get the leaf index
    const leafIndex = parseInt(eventItem.index);

    // 2. Generate the proof for THIS specific leaf
    // This returns an object that contains the siblings array
    const proof = tree.generateProof(leafIndex); 

    // 3. Now you can map the siblings safely
    const pathAsStrings = proof.siblings.map(s => s.toString());

    console.log("Successfully generated path for index:", leafIndex);
    // Iterate through validators to sign
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {
            const cleanPk = pk.replace("0x", "");
            const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
            const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);
            
            console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`);

            // 1. Get the latest state (important for sequential updates)
            console.log(`[Validator #${i + 1}] Validating: ${eventItem.header}::${eventItem.name}`);
            
            // 3. Prepare Message for signing
            // Ensure newData is a BigInt for the signature message
            const currentDataBI = BigInt(leHexToBI(eventItem.newData));
            

            console.log(eventItem);

            const messageInputs = [
                BigInt(oldRoot), 
                BigInt(newRoot), 
                strToField(eventItem.header),
                strToField(eventItem.name),
                currentDataBI 
            ];

            // 4. Sign the state transition
            let signature = await signRotationMessage(babyJubData.privKey, messageInputs);
            
            // 5. Persist the tree update in your local state
            await updateState('variables', { 
                varTree: tree, 
                oldRoot: oldRoot, 
                newRoot: newRoot,
            });

            // 6. Build Supra Payload
            // Note: We send the roots as strings or U256 depending on your Move contract
            const payload = [
                "variables",
                newRoot, 
                signature.r8x, 
                signature.r8y, 
                signature.s, 
                signature.message,
                [oldRoot,newRoot, eventItem.header,eventItem.name,currentDataBI.toString(),(eventItem.index), ...pathAsStrings]
            ];

            const client = await getSupraClient("https://rpc-testnet.supra.com");
            await SupraSendTransaction(client, senderAcc, payload, "validate");

        } catch (error) {
            console.error(`Error processing validator at index ${i}:`, error);
        }
    }
}

async function check_for_events() {
    let state = await getState('variables');
    let fetchedEvents = await fetchSupraEvent("ax");
    console.log("Old Variables root: ", state.varTree.getRoot());
    // Initialize state tracking
    let storedEvents = state.events || [];
    let processedIds = state.processedEventIds || []; // Array of sequence_numbers

    // 1. Identify new events (Not in history AND not processed)
    let newEvents = fetchedEvents.filter(fetched => {
        // Navigate into the data to find your variable index
        // Note: Adjust 'fetched.event.data.index' based on your specific Supra event structure
        const varIndex = fetched.data.data.index; 
        const txHash = fetched.transaction_hash;
        
        // Create a unique ID for this specific update
        const eventFingerprint = `${varIndex}_${txHash}`;

        const isNotStored = !storedEvents.some(stored => stored.fingerprint === eventFingerprint);
        const isNotProcessed = !processedIds.includes(eventFingerprint);

        return isNotStored && isNotProcessed;
    });

    if (newEvents.length > 0) {
        console.log(`Found ${newEvents.length} new events!`);
            const poseidon = await buildPoseidon();
            
            let validators = await get_validators();
            const CIRCUIT_N_VALIDATORS = 16; 
            const CIRCUIT_TREE_DEPTH = 4;   

            // 1. Build the Tree
            const validatorsForTree = validators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
                pub_key_x: BigInt(v.pub_key_x),
                pub_key_y: BigInt(v.pub_key_y),
                staked: BigInt(v.staked)
            }));

            const valTree = new PoseidonMerkleTree(validatorsForTree, poseidon, CIRCUIT_TREE_DEPTH, "validators");
            updateState('variables', { valTree: valTree, validators: validators, validatorRoot: valTree.getRoot() });
            console.log("Validator root: ", valTree.getRoot());

        for (const event of newEvents) {
            try {
                // 2. Perform the heavy lifting
                console.log(`Processing event: ${event.data.data}`);
                const allSignatures = event.data.sigs.data.map(item => item.value);
                const data = await dataToVariable(event.data.data);
                console.log("Converted Data:", data);
                await updateState('variables', { sigs: allSignatures, variable: data });
                await complete_work();

                // 3. Mark as processed immediately so we don't repeat on crash
                processedIds.push(event.sequence_number);
                
                // Keep the "processed checklist" clean (optional, same size as events)
                if (processedIds.length > 100) processedIds.shift();

                console.log(`Successfully processed event: ${event.sequence_number}`);
            } catch (err) {
                console.error(`Failed to process event ${event.sequence_number}:`, err);
                // We don't add it to processedIds, so it will retry next poll
            }
        }


        // 4. Update the rolling window of stored events
        let updatedEvents = [...storedEvents, ...newEvents].slice(-100);

        await updateState('variables', { 
            events: updatedEvents,
            processedEventIds: processedIds 
        });
    } else {
        console.log("No new events found.");
    }
}


async function startPolling(intervalMs = 50000) {

    const poseidon = await buildPoseidon(); // Must define this!
    const TREE_DEPTH = 16; 

    const tree = new PoseidonMerkleTree([], poseidon, TREE_DEPTH, "variables");
    
    // 3. Update the CORRECT namespace
    await updateState('variables', { varTree: tree, oldRoot: tree.getRoot(),variables: []});

    // Create a named function so we can call it recursively
    const run = async () => {
        console.log("Fetching Variables...");
        let new_variables = await get_all_variables();
        let data = getState('variables');
        if (data.variables !== new_variables) {

            let changed_variables = await detect_variable_changes(data.variables, new_variables);
            console.log("ℹ️ Changed variables:", changed_variables);

            // Inside startPolling
            for (const el of changed_variables) {
                console.log("Starting Validation... for ", el);
                
                // 1. Update the tree and get the roots for THIS specific variable
                await AllValidate(BRIDGE_CONFIG, el); 
                
                // 2. IMPORTANT: You must build the input for THIS state now
                // If you wait until the loop finishes, the tree is already "in the future"
                console.log("Building Input...");
                await build_input("variables",await getState('variables'));
                
                // 3. Now you can check for events or run the prover
                console.log("Checking for events...");
                await check_for_events(); 
            }
        };
        setTimeout(run, intervalMs);
    };

    // Return the result of the first call so the workflow can wait for it
    return run(); 
}

async function prepareRootsForWitness(tree, eventItem, poseidon) {
    const F = poseidon.F;
    const index = parseInt(eventItem.index);
    const genesisEmptyHash = F.toObject(poseidon([0n, 0n, 0n]));
    
    // 1. Get current state of the slot
    const currentLeaf = tree.leaves[index];

    // 2. VIRTUAL STEP: Move from Genesis [0,0,0] to Initialized [Header, Name, 0]
    // We only do this if the slot is currently a "Genesis Zero"
    if (currentLeaf === genesisEmptyHash) {
        const initializedEmptyLeaf = poseidon([
            strToField(eventItem.header),
            strToField(eventItem.name),
            0n 
        ]);
        tree.update(index, initializedEmptyLeaf);
        console.log(`[Tree] Initialized slot ${index} for ${eventItem.header} with empty leaf ${poseidon.F.toString(initializedEmptyLeaf)}`);
    }

    // This is now our "Baseline" root (the 'Before' state for the proof)
    const oldRootForProof = tree.getRoot(); 

    const dataToHash = leHexToBI(eventItem.newData);

    // 3. ACTUAL STEP: Move from [Header, Name, 0] to [Header, Name, NewData]
    const finalLeaf = poseidon([
        strToField(eventItem.header),
        strToField(eventItem.name),
        dataToHash
    ]);
    tree.update(index, finalLeaf);
    console.log(`[Tree] updated slot ${index} for ${eventItem.header} | ${eventItem.name} with final leaf ${poseidon.F.toString(finalLeaf)}, data: ${dataToHash}`);
    // This is our 'After' state
    const newRootForProof = tree.getRoot();

    return {
        oldRoot: oldRootForProof.toString(),
        newRoot: newRootForProof.toString()
    };
}

async function complete_work(){
    console.log("Preparing Proof...");
    //let result = await prepareBatch("variables");
    // if(result){
    //     console.log("✅ Proof Prepared:", result);
    // };
    console.log("Evm ZK Run...");
    await evm_run("validators", "load_variables_evm");
    console.log("Sui ZK Run...");
    await sui_run("validators", "load_variables_sui");

}
// Start the sequence
startPolling();