const { storeEvents, getCursor, getPendingEvents }=  require ("./db/events_db.js");
const { getValidatorConfig, nativeBcsDecode } = require("./global_util.js");


let config;

const eventTypes = {
    consensus: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraEventV34::ConsensusEvent",
    crosschain: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraEventV34::CrosschainEvent",
    validate:"0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraEventV34::ValidationEvent",
    proof:"0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraEventV34::ValidationEvent"
};

async function syncAllEvents() {
    for (const [category, eventKey] of Object.entries(eventTypes)) {
        console.log(`Syncing ${category}...`);
        config = await getValidatorConfig();
        
        let currentCursor = getCursor(category); 

        const url = new URL("http://127.0.0.1:3000/api/supra-events");
        url.searchParams.set("type", eventKey);

        if (!currentCursor) {
            url.searchParams.set("start_height", config.start_height);
        } else {
            url.searchParams.set("start", currentCursor);
        }

        try {
            const response = await fetch(url.toString());
            if (!response.ok) throw new Error(`Fetch failed: ${response.status}`);

            const result = await response.json();
            //console.log(result);    
            // Extract the actual array from the nested result
            // Based on your log, it's result.data.data
            const eventsArray = result.data?.data || result.data || [];
            const nextCursor = result.next_cursor || result.cursor;
            //console.log(eventsArray);
            if (eventsArray.length === 0) {
                console.log(`[${category}] No new events`);
                if (nextCursor) updateSavedCursor(category, nextCursor);
                continue;
            }

            let formattedEvents = eventsArray.map(item => {
                // 1. Dig into the event structure
                const eventBody = item.event || {};
                const eventData = eventBody.data || {}; 

                // 2. Extract the "Request Bridge" name and the fields array
                // Since name and aux are at the same level in eventData
                const friendlyName = eventData.name; 
                const fields = Array.isArray(eventData.aux) ? eventData.aux : [];
                
                return {
                    tx_hash: item.transaction_hash, 
                    block: item.block_height,
                    // The technical Move type (0x...ConsensusEvent)
                    move_type: eventBody.type, 
                    // The friendly name you wanted ("Request Bridge")
                    type_name: friendlyName, 
                    data: fields.map(field => {
                        let val = nativeBcsDecode(field.value, field.type);
                        
                        if (field.name === 'identifier' && (val instanceof Uint8Array || Array.isArray(val))) {
                            val = Buffer.from(val).toString('hex');
                        }
                        
                        return {
                            name: field.name,
                            type: field.type,
                            value: val
                        };
                    })
                };
            });

            // Use the correct function name from your db.js
            // We use 'consensus' or 'crosschain' as the type for the table logic
            // Assuming category maps to one of those or you can pass category directly
            storeEvents(formattedEvents, category, nextCursor);
console.log(JSON.stringify(formattedEvents, null, 2));
            console.log(`Successfully synced ${formattedEvents.length} events for ${category}`);

        } catch (error) {
            console.error(`Error syncing ${category}:`, error.message);
        }
        
        await new Promise(r => setTimeout(r, 100));
    }
}

//console.log(config);
async function runSyncLoop() {
    try {
        await syncAllEvents(); 
        console.log(`--- Sync Cycle Complete. Sleeping for ${ config.rate}ms ---`);
    } catch (err) {
        console.error("Critical error in sync loop:", err);
    } finally {
        setTimeout(runSyncLoop, config.rate);
    }
}

async function test(){
    await syncAllEvents();
    console.log(getPendingEvents("consensus"));
    console.log(getPendingEvents("crosschain"));

}
test();
module.exports = { runSyncLoop };