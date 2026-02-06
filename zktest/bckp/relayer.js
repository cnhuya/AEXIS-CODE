const { getSupraClient, getSupraAccFromPrivKey, SupraSign, SupraSendTransaction, fetchSupraEvent } = require("../util/supra/supra_util.js");
const { strToField, convertLittleEndian,leHexToBI, nativeBcsDecode } = require('../util/global_util.js');
const { updateState, getState } = require('../util/state.js');
const { HexString, SupraAccount, SupraClient, BCS, Deserializer } = require("supra-l1-sdk");
const { PoseidonMerkleTree, signRotationMessage, generateGenesisRoot, deriveBabyJubKey, generateGenericRoot, prepareValidators } = require("../util/zk/zk_builders.js");
const { get_validators, get_epoch } = require("../util/fetchers.js");

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

async function sendRelayerMessage(client, signer, ) {
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

            await SupraSendTransaction(client, signer, payload3, "validate");
}

async function fetchConsensus() {
    try {
        // 1. Get previously processed events from state
        let relayerState = getState('relayer') || {};
        let oldEvents = relayerState.processedHashes || [];

        let response = await fetchSupraEvent("consensus");

        if (!Array.isArray(response)) {
            console.log("Response is not an array as expected:", response);
            return [];
        }

        // 2. Filter out events that we have already processed
        let newRawEvents = response.filter(item => !oldEvents.includes(item.hash));

        if (newRawEvents.length === 0) {
            console.log("No new unique events found.");
            return [];
        }

        // 3. Format only the NEW events using Native SDK Deserialization
        let formattedEvents = newRawEvents.map(item => {
            const fields = (item.data && Array.isArray(item.data.aux)) ? item.data.aux : [];
            
            return {
                tx_hash: item.hash,
                block: item.block,
                data: fields.map(field => {
                    return {
                        name: field.name,
                        type: field.type,
                        // Replaced manual logic with nativeBcsDecode
                        value: nativeBcsDecode(field.value, field.type)
                    };
                })
            };
        });

        // 4. Update state: Append new hashes and keep only the last 100 for memory efficiency
        let updatedHashes = [...oldEvents, ...newRawEvents.map(item => item.hash)].slice(-100);
        updateState('relayer', { 
            processedHashes: updatedHashes 
        });

        console.log(`Successfully deserialized ${formattedEvents.length} new events.`);
        return formattedEvents;

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

async function Validate(config, event, consensus_type, fun) {
    // Using entries() gives us both the index (i) and the private key (pk)
    for (const [i, pk] of config.privateKeyHexs.entries()) {
        try {

            console.log(event);

            const cleanPk = pk.replace("0x", "");
            const senderAcc = new SupraAccount(Buffer.from(cleanPk, "hex"));
            console.log(`Processing Validator #${i + 1}: ${senderAcc.address()}`); 
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

async function startRelayer() {
    console.log("Starting Relayer...");
    const events = await fetchConsensus();
    epoch = await get_epoch();
    if (!events || events.length === 0) {
        console.log("No new events to process.");
        return;
    }

    for (const event of events) {
        console.log(`\n--- Validating Event: ${event.tx_hash} ---`);
        
        console.log(JSON.stringify(event, null, 2));
        // --- EXTRACTION LOGIC ---
        // Look for the object where name is 'consensus_type'
        const consensus_typeField = event.data.find(field => field.name === 'consensus_type');
        const fun_typeField = event.data.find(field => field.name === 'consensus_type');
        
        // Extract the value ('zk', 'optimistic', etc.). Fallback to 'unknown' if not found.
        const consensus_type = consensus_typeField ? consensus_typeField.value : 'unknown';
        const fun = fun_typeField ? fun_typeField.value : 'unknown';

        // Pass it as the third argument
        //await Validate(BRIDGE_CONFIG, event, consensus_type, fun);
    }
    
    console.log("\nAll events processed.");
}

// Helper to handle the top-level execution
startRelayer().catch(console.error);
