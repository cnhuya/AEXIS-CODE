const { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, fetchSupraEvent } = require("../util/supra/supra_util.js");
const { strToField, convertLittleEndian, extractCoinName, addLengthPrefix, getValidatorConfig, getUserNonce, convertStrToAddress, convertTokenStrToAddress, nativeBcsDecode, split256BitValue, fieldToStr, extractEventData, convertChainStrToID, extractEventTypes, convertVaultStrToAddress, convertVaultAddrToStr } = require('../util/global_util.js');
const { updateState, getState } = require('../util/state.js');
const { HexString, SupraAccount, SupraClient, BCS, Deserializer } = require("supra-l1-sdk");
const { PoseidonMerkleTree, ProtocolState, prepare_leaves, signRotationMessage, generateGenesisRoot, deriveBabyJubKey, generateGenericRoot, prepareValidators, prepareBalances, generateIndex } = require("../util/zk/zk_builders.js");
const { build_input } = require("../util/zk/input_builders.js");
const { prepareBatch } = require("../util/prover.js");
const { get_validators, get_epoch, get_validators_signatures, extractValidatorsFromSigs } = require("../util/fetchers.js");
const { storeBalances, updateUserBalance, getAllBalancesRaw } = require('../util/db/balances_db.js');
const { storeEvents } = require('../util/db/events_db.js');
const { getEvmClient, getEvmAccFromPrivKey, EvmSign, EvmSendTransaction, fetchEvmEvent, getEvmAccFromEnv, getActiveRoot, evmEncode, convertSupraTypeToEvm } = require("../util/evm/evm_util.js");
const { fetchSuiEvent } = require("../util/sui/sui_util.js");
const { buildPoseidon, buildEddsa } = require("circomlibjs");
// Change this in relayer.js
const { Worker } = require('node:worker_threads');
const path = require('path');
const { getPendingEvents } = require('../util/db/events_db.js');
const fs = require("fs");
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
 
let epoch = 0;
let protocol_state;
async function sync_all_balances() {
    let currentPage = 0;
    let keepFetching = true;

    while (keepFetching) {
        console.log(`Fetching page ${currentPage}...`);
        try {
            const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
                method: 'POST',
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraTokensOmnichainV2::return_outflow_page",
                    type_arguments: [],
                    arguments: [currentPage.toString()]
                })
            });

            const body = await response.json();
            const result = body.result?.[0];

            // If data is empty or missing, stop the loop
            if (!result || !result.data || result.data.length === 0) {
                console.log("🏁 No more data found. Sync complete.");
                keepFetching = false;
            } else {
                // Pass the data to the store function
                storeBalances(result.data);
                currentPage++; 
            }
        } catch (error) {
            console.error("🚨 Pagination error:", error);
            keepFetching = false;
        }
    }
}
async function onLoad() {
    let balTree = await prepare_leaves("balances");
    let valTree = await prepare_leaves("validators");
    let varTree = await prepare_leaves("variables");

    protocol_state = new ProtocolState(balTree, valTree, varTree);

}

function runProofWorker(taskData) {
    return new Promise((resolve, reject) => {
        // Use path.resolve to ensure the absolute path is correct
        const workerPath = path.resolve(__dirname, '../util/workers.js');
        
        const worker = new Worker(workerPath, {
            workerData: {} 
        });
        
        worker.postMessage(taskData);
        
        worker.on('message', (res) => {
            if (res.success) resolve(res);
            else reject(new Error(res.error));
        });
        
        worker.on('error', reject);
        worker.on('exit', (code) => {
            if (code !== 0) reject(new Error(`Worker stopped with exit code ${code}`));
        });
    });
}

async function fetchConsensus() {
    try {
        console.log("Fetching Consensus Events...");
        let events = getPendingEvents("consensus");
        for (const event of events) {
            console.log(`\n--- Validating Event: ${event.transaction_hash} ---`);
            
            console.log(JSON.stringify(event, null, 2));
            const consensus_type = event.event_data.find(field => field.name === 'consensus_type');

            // Pass it as the third argument
            await Validate(BRIDGE_CONFIG, event, consensus_type.value, event.type_name);
        }

    } catch (error) {
        console.error("Error processing consensus events:", error);
    }
}


/*async function fetchCrosschainEvents() {
    try {
        console.log("Fetching Crosschain Events...");
        let events = getPendingEvents("crosschain");
        for (const event of events) {
            console.log(`\n--- Validating Event: ${event.transaction_hash} ---`);
            
            console.log(JSON.stringify(event, null, 2));
            const consensus_type = event.event_data.find(field => field.name === 'consensus_type');

            // Pass it as the third argument
            await Validate(BRIDGE_CONFIG, event, consensus_type.value, event.type_name);
        }

    } catch (error) {
        console.error("Error processing consensus events:", error);
    }
}
 */
async function fetchCrosschainEvents() {
    try {
        console.log("Fetching Crosschain Events...");
        let events = getPendingEvents("crosschain");
        if (events.length === 0) return;
        let poseidon = await buildPoseidon();
        let config = await getValidatorConfig();
        let data = getState('relayer');

        // Process in chunks based on MAX_WORKERS
        for (let i = 0; i < events.length; i += config.MAX_WORKERS) {
            const batch = events.slice(i, i + config.MAX_WORKERS);
            console.log(`Processing batch of ${batch.length} proofs...`);
            
            const proofPromises = [];

            // --- SEQUENTIAL SECTION (Fast) ---
            // We must update the tree one-by-one to get the correct linked roots
            for (const event of batch) {
                const stateSnapshot = await manager.processTransaction(event, poseidon);

                let x = extractEventData(event, ["identifier", "addr", "token", "chain", "total_outflow", "additional_outflow"]);
                
                let identifier = addLengthPrefix(x.identifier);
                console.log("identifier", identifier);

                // 4. Fetch signatures & validator info (can stay here or move to worker)
                let sigs = await get_validators_signatures(identifier.toString());
                let validators = await get_validators();
                let oldValidators = data.oldValidators;
                let valTree = await prepareValidators(validators, oldValidators);
                console.log(validators);
                console.log(stateSnapshot);

                const workerInputs = {
                    ...stateSnapshot,
                    valTreeData: valTree.tree.serialize(), // Use the new method
                    sigs: sigs,
                    validators: validators,
                    event: event
                };

                // This part is slow (~10s), so we don't 'await' it here
                const proofPromise = runProofWorker(workerInputs).then(proof => {
                  //  return submitToChain(proof); // Handle submission once ready
                });

                proofPromises.push(proofPromise);
            }

            // Wait for all ZK workers in this batch to finish
            const results = await Promise.all(proofPromises);
            results.forEach(res => console.log("✅ Worker Finished Proof for Tx:", res.tx_hash));
            
            // Optional: Submit this batch of proofs to the destination chain here
        }

    } catch (error) {
        console.error("Error processing consensus events:", error);
    }
}

// Function that looks for deposits and withdraws events for each supported chain, proccesses them and sends validation function to settlement layer
async function fetchBridge() {
    let state = await getState('balances') || {};
    const chains = ["base", "monad"];
    const eventTypes = ["deposit"];
    
    let storedEvents = state.events || [];
    let processedIds = state.processedEventIds || [];

    // Outer Loop: Iterate through each chain
    for (const chain of chains) {
        // Inner Loop: Iterate through each event type (deposit/withdraw)
        for (const eventType of eventTypes) {
            console.log(`Checking ${eventType}s on ${chain.toUpperCase()}...`);
            
            try {
                let fetchedData = await fetchEvmEvent(chain, eventType);

                // Flatten structure: fetchedData[chain] contains the objects indexed by "Address | Name"
                let allFetchedEvents = Object.entries(fetchedData[chain] || {}).flatMap(([identifier, transactions]) => {
                    const [address, name] = identifier.split(" | ");
                    
                    return transactions.map(tx => ({ 
                        ...tx, 
                        chain,           // Store which chain this came from
                        eventType,       // Store if this was a deposit or withdraw
                        token_name: name // Keep the token name for the validator
                    }));
                });

                // Filter for new unique events
                let newEvents = allFetchedEvents.filter(fetched => {
                    const eventFingerprint = `${fetched.hash}_${fetched.block}_${eventType}`;
                    const isNotStored = !storedEvents.some(stored => stored.fingerprint === eventFingerprint);
                    const isNotProcessed = !processedIds.includes(eventFingerprint);

                    fetched.fingerprint = eventFingerprint;
                    return isNotStored && isNotProcessed;
                });

                if (newEvents.length > 0) {
                    console.log(`Found ${newEvents.length} new ${eventType} events on ${chain}!`);
                    
                    for (const event of newEvents) {
                        try {
                            console.log(`Processing ${event.token_name} ${eventType} | Hash: ${event.hash}`);
                            
                            // Dynamically call the correct validation function
                            if (eventType === 'deposit') {
                                await ValidateDeposit(BRIDGE_CONFIG, event, chain);
                            } else {
                                await ValidateWithdraw(BRIDGE_CONFIG, event, chain);
                            }

                            await sync_all_balances();
                            
                            processedIds.push(event.fingerprint);
                            if (processedIds.length > 100) processedIds.shift();
                            
                            // Add to stored list for the final state update
                            storedEvents.push(event);

                            console.log(`Successfully processed: ${event.hash}`);
                        } catch (err) {
                            console.error(`Failed to process event ${event.hash}:`, err);
                        }
                    }
                }
            } catch (err) {
                console.error(`Error fetching ${eventType} events for ${chain}:`, err);
            }
        }
    }

    // Final update to state after all chains and types are checked
    let updatedEvents = storedEvents.slice(-100);
    await updateState('balances', { 
        events: updatedEvents,
        processedEventIds: processedIds 
    });
    
    console.log("Event check cycle complete.");
}
async function ValidateDeposit(config, event, chain) {
    // Using entries() gives us both the index (i) and the private key (pk)
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {
            console.log(event);
            if(chain == "evm"){
                EvmSendTransaction(getEvmAccFromEnv(await getEvmClient(chain), 'acc1'), chain, [event.currentRoot, event.newRoot, event.epoch], "Active Validators Changed");
            }

            let payload = [];


            let data = getState('validators');
            console.log(data);

            if (consensus_type == "zk"){
                const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);

                if(fun == "Active Validators Changed"){
                    let new_validators = await get_validators();
                    let zk_val = await prepareValidators(new_validators, data.oldValidators);
                    let signature = await signRotationMessage(babyJubData.privKey, [zk_val.currentRoot, zk_val.newRoot, epoch]);
                    payload = [epoch, zk_val.currentRoot, signature.r8x, signature.r8y, signature.s, signature.message];

                    updateState('validators', { oldValidators: new_validators });
                } else if (fun == "validate_state") {
                    
                }
            } else if (consensus_type == "native") {
                if(fun == "Deposit"){
                    payload = [event.currentRoot, event.newRoot, event.epoch];
                } 
            }

            await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload, fun);

        } catch (error) {
            console.error(`Error processing key at index ${i}:`, error);
        }
    }
}
async function Validate_proof(event, proof, inputs) {
    const config = BRIDGE_CONFIG
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {
            const cleanPk = pk.replace("0x", "");
            const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
            console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`); 

            let payload_types = [];

            // Payload for the Supra transaction
            payload = [event.index, proof, inputs];
            console.log("Constructed Payload:", payload);

            await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload, "register_proof_event", payload_types);
            
            
        } catch (error) {
            console.error(`Error processing key at index ${i}:`, error);
        }
    }
}

async function Validate(config, event, consensus_type, fun) {
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {
            const cleanPk = pk.replace("0x", "");
            const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
            console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`); 

            let payload = [];
            let payload_types = [];
            let poseidon = await buildPoseidon();
            let data = getState('relayer');
            console.log(`Consensus Type: [${consensus_type}], Fun Type: [${fun}]`); 
            updateState('relayer', { event: event });
            let new_validators = await get_validators();
            if (consensus_type == "zk") {
                const babyJubData = await deriveBabyJubKey(senderAcc, config.derivationMessage);

                //"Active Validators Changed
                if (fun == "abc") {
                    let zk_val = await prepareValidators(new_validators, data.oldValidators);
                    let signature = await signRotationMessage(babyJubData.privKey, [zk_val.currentRoot, zk_val.newRoot, epoch]);
                    payload = [epoch, zk_val.currentRoot, signature.r8x, signature.r8y, signature.s, signature.message];

                    updateState('validators', { oldValidators: new_validators });
                } 
                else if (fun == "Request Bridge") {
                    let x = extractEventData(event, ["addr", "nonce", "token", "chain", "provider", "additional_outflow", "total_outflow", "timestamp"]);
                    
                    // 1. USE THE UNIFIED STATE UPDATE
                    // This ensures that even if 5 bridge requests come in fast, 
                    // the roots and nonces chain correctly.
                    let zk_val = await manager.processTransaction(event, poseidon); 
                    
                    // 2. Prepare validator tree for the proof
                    let zk_validators = await prepareValidators(new_validators, data.oldValidators);

                    let userAddress = split256BitValue(x.addr);
                    let storageID = strToField(x.token);
                    let vaultID = strToField(x.provider);
                    let chainTo = await convertChainStrToID(x.chain);
                    const finalBalance = BigInt(zk_val.newBalance);
                    console.log("user nonce: ", BigInt(x.nonce));

                    const nullifier = poseidon([
                        BigInt(userAddress.low),
                        BigInt(userAddress.high),
                        BigInt(x.nonce),
                    ]);
                    let objNulifier = poseidon.F.toObject(nullifier).toString();

                    const messageToSign = [
                            BigInt(zk_val.oldRoot),
                            BigInt(zk_val.newRoot),
                            BigInt(userAddress.low),
                            BigInt(userAddress.high),
                            BigInt(storageID),
                            BigInt(vaultID),
                            BigInt(finalBalance), 
                            BigInt(chainTo),
                        ];
                        
                    // 1. Generate the signature
                    let signature = await signRotationMessage(babyJubData.privKey, messageToSign);

                    payload_types = ["string","string", "vector<u8>", "string","string","string","u64","string","string","string","string","string","string", "string", "u256", "u64"]
                    let bundledArray = await bundle(
                            ["consensus_type", "event_type", "addr", "symbol", "chain", "provider", "amount",  "s_r8x", "s_r8y", "s", "validator_root", "old_root", "new_root", "nullifier", "nonce", "time"],
                            ["zk", fun, x.addr, x.token, x.chain, x.provider, (BigInt(x.additional_outflow) + BigInt(x.total_outflow)).toString(), signature.r8x, signature.r8y, signature.s, zk_validators.newValRoot, zk_val.oldRoot, zk_val.newRoot, objNulifier, x.nonce, x.timestamp]
                        );
                    const keys = bundledArray.map(item => item.type_name);
                    const values = bundledArray.map(item => item.payload.toString()); 
                    // Payload for the Supra transaction
                    payload = [keys, values];
                    console.log("Constructed Payload:", payload);
                } else {
                    console.log("Unknown function:", fun);
                    break;
                }
            } else if (consensus_type == "native") {
                if(fun == "Bridge Deposit"){
                    payload_types = ["string","string","pure","pure", "pure", "string","string","string","u64","string", "u64"]
                    const chain_capitalized = `${event.chain[0].toUpperCase()}${event.chain.slice(1)}`;
                    if(event.chain != "sui"){
                        let provider = await convertVaultAddrToStr(event.vault, chain_capitalized);
                        let signature = await SupraSign(senderAcc, [event.user, event.amount, event.token, chain_capitalized, provider, event.hash, event.timestamp], ["address", "u64", "string", "string", "string", "string", "u64"]);
                        
                        let bundledArray = await bundle(
                                ["consensus_type", "event_type", "signature", "message", "addr","symbol", "chain", "provider", "amount", "hash", "time"],
                                ["native", fun, signature.signature, signature.message, event.user, await convertStrToAddress(chain_capitalized, event.token), chain_capitalized, provider, BigInt(event.amount), event.hash, event.timestamp]
                            );
                        console.log(bundledArray);
                        const keys = bundledArray.map(item => item.type_name);
                        const values = bundledArray.map(item => item.payload.toString()); 

                        payload = [keys, values, payload_types];
                    } else if (event.chain == "sui"){
                        let signature = await SupraSign(senderAcc, [event.user, event.amount, event.token_type, chain_capitalized, event.provider, event.hash, event.timestamp], ["address", "u64", "string", "string", "string", "string", "u64"]);
                        let bundledArray = await bundle(
                            ["consensus_type", "event_type", "signature", "message", "addr","symbol", "chain", "provider", "amount", "hash", "time"],
                            ["native", fun, signature.signature, signature.message, event.user, event.token_type, chain_capitalized, event.provider, BigInt(event.amount), event.hash, event.timestamp]
                        );
                        const keys = bundledArray.map(item => item.type_name);
                        const values = bundledArray.map(item => item.payload.toString()); 

                        payload = [keys, values, payload_types];
                    }
                }  else {
                    console.log("Unknown function:", fun);
                    break;
                }
            } else if (consensus_type == "proof") {
                if(fun == "Crosschain Event"){
                        
                    await build_input("relayer");
                    
                    let signature = await SupraSign(senderAcc, [event.user, event.amount, event.token_type, chain_capitalized, event.provider, event.hash, event.timestamp], ["address", "u64", "string", "string", "string", "string", "u64"]);
                        let bundledArray = await bundle(
                            ["consensus_type", "event_type", "signature", "message", "addr","symbol", "chain", "provider", "amount", "hash", "time"],
                            ["native", fun, signature.signature, signature.message, event.user, event.token_type, chain_capitalized, event.provider, BigInt(event.amount), event.hash, event.timestamp]
                        );
                        const keys = bundledArray.map(item => item.type_name);
                        const values = bundledArray.map(item => item.payload.toString()); 

                        payload = [keys, values, payload_types];
                }  else {
                    console.log("Unknown function:", fun);
                    break;
                }
            } else {
                console.log("Unknown consensus type:", consensus_type);
                break;
            }

         //   await SupraSendTransaction(await getSupraClient("https://rpc-testnet.supra.com"), senderAcc, payload, "register_event", payload_types);
            
            
        } catch (error) {
            console.error(`Error processing key at index ${i}:`, error);
        }
    }
}

async function bridge_to_supra() {
    //let result_evm = await fetchEvmEvent("base", "deposit");
    let result_sui = await fetchSuiEvent("deposit");
   // console.log(result_sui);
    //for (const chain in result_evm) {
      //  const vaults = result_evm[chain];

        //for (const vaultAddress in vaults) {
          //  const transactions = vaults[vaultAddress];

            // FIX: Use for...of instead of .forEach to allow 'await'
            for (const tx of result_sui) {
                //const singleEvent = rebuildEvent(chain, vaultAddress, tx);
                
                console.log("Processing Event:", tx);

                // Now 'await' will correctly pause the loop until validation finishes
                await Validate(BRIDGE_CONFIG, tx, "native", "Bridge Deposit");
            }
        //}
    //}
}

async function bundle(names, data) {
    // We map over the names array and use the index 'i' 
    // to pair it with the corresponding entry in 'data'
    const bundledData = names.map((name, i) => {
        return {
            type_name: name,
            payload: data[i]
        };
    });

    return bundledData;
}
async function startRelayer() {
    console.log("Starting Relayer...");
    console.log("First Load..");
    await onLoad();
    // This starts BOTH fetches at the same time

    await Promise.all([
      // await fetchConsensus(),
       await fetchCrosschainEvents(),
    ]);

/*    if (!events || events.length === 0) {
        console.log("No new events to process.");
        return;
    } 

    for (const event of events) {
        console.log(`\n--- Validating Event: ${event.tx_hash} ---`);
        
        console.log(JSON.stringify(event, null, 2));
        // --- EXTRACTION LOGIC ---
        // Look for the object where name is 'consensus_type'

        await ValdiateCrossChainEvent(event);

        //const consensus_typeField = event.data.find(field => field.name === 'consensus_type');
    
        // Extract the value ('zk', 'optimistic', etc.). Fallback to 'unknown' if not found.
        //const consensus_type = consensus_typeField ? consensus_typeField.value : 'unknown';

        // Pass it as the third argument
        //await Validate(BRIDGE_CONFIG, event, consensus_type, event.name);
    }
    
    console.log("\nAll events processed.");*/
}

// Helper to handle the top-level execution
startRelayer().catch(console.error);

module.exports = { Validate_proof };
