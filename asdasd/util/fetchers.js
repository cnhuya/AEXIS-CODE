async function get_validators() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                //0x434efed497f5b9ed8f975dd60df271297e35a1bbe9e4a17bc65920273bfca1c6::QiaraVv12::return_all_active_parents_full
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraValidatorsV40::return_all_active_validators_full",
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

        console.log("Validators:", validatorsArray);
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
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraGenesisV1::return_epoch",
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

function extractValidatorsFromSigs(sigsArray) {
    if (!sigsArray || !Array.isArray(sigsArray)) return [];
    
    return sigsArray.map(sig => ({
        staked: sig.weight, // mapping weight to staked
        pub_key_x: sig.pub_key_x,
        pub_key_y: sig.pub_key_y
    }));
}

async function get_consensus_vote_data(index) {
    try {
        console.log("Checking for index:", index);
        
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraBridgeV40::return_zk_validated_tx",
                type_arguments: [],
                arguments: [index.toString()]
            })
        });

        const body = await response.json();
        
        // 1. Handle RPC errors or empty results
        if (body.error || !body.result || body.result.length === 0) {
            console.warn("No data found or RPC error for index:", index);
            return []; 
        }

        // 2. Access the new structure: result[0].votes.data
        const data = body.result[0]?.data;
        const data_types = body.result[0]?.data_types;
        const votes = body.result[0]?.votes;
        
        return {data_types: data_types, data: data, votes: votes};

    } catch (error) {
        console.error("🚨 Validator Signatures Fetch error:", error);
        return [];
    }
}
async function get_validators_signatures(index) {
    try {
        console.log("Checking for index:", index);
        
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraBridgeV40::return_zk_validated_tx",
                type_arguments: [],
                arguments: [index.toString()]
            })
        });

        const body = await response.json();
        
        // 1. Handle RPC errors or empty results
        if (body.error || !body.result || body.result.length === 0) {
            console.warn("No data found or RPC error for index:", index);
            return []; 
        }

        // 2. Access the new structure: result[0].votes.data
        const validatorsData = body.result[0]?.votes?.data;

        // 3. Validation check
        if (!Array.isArray(validatorsData)) {
            console.error("Unexpected data format: votes.data is not an array");
            return [];
        }

        // 4. Map the data to your desired format
        const validatorsArray = validatorsData.map(v => {
            const val = v.value;
            return {
                address: v.key,
                // Using 'weight' from your new JSON instead of 'staked'
                weight: val.weight ? BigInt(val.weight).toString() : "0", 
                pub_key_x: val.pub_key_x,
                pub_key_y: val.pub_key_y,
                s: val.s,
                s_r8x: val.s_r8x,
                s_r8y: val.s_r8y,
                // Note: 'message' and 'index' weren't in your sample JSON 'value' object,
                // if they are missing, they will be undefined.
                message: val.message,
                index: val.index 
            };
        });

        //console.log("Successfully fetched validators:", validatorsArray);
        
        // Update your local state
        if (typeof updateState === 'function') {
            updateState('validators', { sigs: validatorsArray });
        }

        return validatorsArray;

    } catch (error) {
        console.error("🚨 Validator Signatures Fetch error:", error);
        return [];
    }
}
module.exports = { get_validators, extractValidatorsFromSigs, get_epoch, get_consensus_vote_data, get_validators_signatures };