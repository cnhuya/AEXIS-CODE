const fs = require('fs');
const path = require('path');
async function getFunctionData(chain, actionName) {
    const functionsPath = path.join(__dirname, '../config/functions.json');
    const walletsPath = path.join(__dirname, '../config/wallets.json');

    const functionsData = JSON.parse(fs.readFileSync(functionsPath, 'utf8'));
    const walletsData = JSON.parse(fs.readFileSync(walletsPath, 'utf8'));

    // 1. Case-insensitive lookup for the action
    const chainData = functionsData[chain];
    if (!chainData) throw new Error(`Chain ${chain} not found in config`);

    const actualKey = Object.keys(chainData).find(k => k.toLowerCase() === actionName.toLowerCase());
    const action = chainData[actualKey];

    if (!action) throw new Error(`Action ${actionName} not found for chain ${chain}`);

    // Helper to resolve address from wallets.json using address_ref
    const getAddressFromRef = () => {
        const ref = action.address_ref;
        const addr = walletsData[chain]?.[ref];
        if (!addr) throw new Error(`Address reference "${ref}" not found in wallets.json for chain ${chain}`);
        return addr;
    };

    // 2. Handle EVM Chains (Base, Ethereum, etc.)
    if (chain !== "sui" && chain !== "supra") {
        let functionName;
        if (typeof action.contract_abi === 'object' && action.contract_abi !== null) {
            functionName = action.contract_abi.name;
        } else if (typeof action.contract_abi === 'string') {
            const match = action.contract_abi.match(/function\s+(\w+)/);
            functionName = match ? match[1] : null;
        }

        return {
            contract_address: action.contract_address, 
            abi: Array.isArray(action.contract_abi) ? action.contract_abi : [action.contract_abi],
            functionName: functionName
        };
    }

    // 3. Handle Sui
    if (chain === "sui") {
        return {
            package: action.package || getAddressFromRef(), // Uses package if defined, else wallet ref
            module_name: action.module_name,
            function_name: action.function_name,
            args: action.args
        };
    }

    // 4. Handle Supra
    if (chain === "supra") {
        return {
            module_address: getAddressFromRef(), // Resolves "main" -> "0x434..."
            module_name: action.module_name,
            function_name: action.function_name,
            args: action.args
        };
    }

    throw new Error(`Unsupported chain type: ${chain}`);
}
async function getEventData(chain, actionName) {
    const functionsPath = path.join(__dirname, '../config/events.json');
    const functionsData = JSON.parse(fs.readFileSync(functionsPath, 'utf8'));

    const action = functionsData[chain]?.[actionName];
    if (!action) throw new Error(`Action ${actionName} not found for chain ${chain}`);

    // Check if it's an EVM chain (Base, Ethereum, etc.)
    if (chain !== "sui" && chain !== "supra") {
        return {
            contractAddresses: action.contract_addresses,
            abi: action.contract_abi, // This is already the array ["event Deposit..."]
            event: "Deposit" // You can hardcode this or extract it with regex if needed
        };
    }

    // Return for Sui/Supra
    return { event: action.event };
}

const loadGeneratedProof = (type) => {
    try {
        // Adjust paths based on your folder structure (../type/proof.json)
        const proofPath = path.join(__dirname, '../zk', type, 'proof.json');
        const publicPath = path.join(__dirname, '../zk', type, 'public.json');

        const proofData = JSON.parse(fs.readFileSync(proofPath, 'utf8'));
        const publicSignals = JSON.parse(fs.readFileSync(publicPath, 'utf8'));

        return {
            pA: proofData.pi_a.slice(0, 2), // SnarkJS uses 3 elements, we need the first 2
            pB: [
                proofData.pi_b[0][1], proofData.pi_b[0][0], // Swap order for EVM compatibility
                proofData.pi_b[1][1], proofData.pi_b[1][0]
            ],
            pC: proofData.pi_c.slice(0, 2),
            publicSignals: publicSignals
        };
    } catch (error) {
        throw new Error(`Failed to load proof files for ${type}: ${error.message}`);
    }
};

async function getPrivKey(chain, accountName) {
    const envKey = `${chain.toUpperCase()}_ACCOUNTS`;
    const rawJson = process.env[envKey];

    if (!rawJson) {
        console.error(`❌ Env variable ${envKey} not found.`);
        return null;
    }

    try {
        // 2. Parse the JSON string from the .env
        const accountMap = JSON.parse(rawJson);

        // 3. Return the specific key
        const privKey = accountMap[accountName];

        if (!privKey) {
            console.error(`❌ Account "${accountName}" not found in ${envKey}`);
            return null;
        }

        return privKey;
    } catch (e) {
        console.error(`❌ Error parsing JSON in ${envKey}:`, e.message);
        return null;
    }
}

async function getValidatorConfig() {
    const configPath = path.join(__dirname, '../config/config.json');
    const configData = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    return configData;
}

async function convertChainStrToID(chainStr) {
    // 1. Validate Input immediately
    if (!chainStr || typeof chainStr !== 'string') {
        console.error("chainStr is invalid:", chainStr);
        return BigInt(0); // Or handle error
    }

    try {
        // 2. Explicitly use global fetch if in a worker
        const fetchMethod = typeof fetch !== 'undefined' ? fetch : globalThis.fetch;
        
        const response = await fetchMethod('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraChainTypesV2::return_all_chain",
                type_arguments: [],
                arguments: []
            })
        });

        const body = await response.json();
        const chainData = body.result?.[0]?.data;

        if (!chainData || !Array.isArray(chainData)) {
            throw new Error("Invalid chain data structure from RPC");
        }

        // 3. Robust Finding Logic
        // We use optional chaining on item.key in case the registry has a null entry
        const entry = chainData.find(item => 
            item?.key?.toString().toLowerCase() === chainStr.toLowerCase()
        );

        if (!entry) {
            throw new Error(`Chain string "${chainStr}" not found in registry`);
        }

        console.log("Found chainid:", entry.value);
        return BigInt(entry.value);

    } catch (error) {
        console.error("Error in convertChainStrToID:", error.message);
        throw error;
    }
}

async function convertTokenStrToAddress(chain, token) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraTokenTypesV2::get_token_address_from_name",
                type_arguments: [],
                arguments: [chain.toString(), token.toString()]
            })
        });

        const body = await response.json();
        // Access result[0].data based on your provided JSON structure
        const addr = body.result?.[0];

        console.log("addr:",addr);
        return addr; // Returns 0, 1, 2, 3, or 4

    } catch (error) {
        console.error("Error converting chain string to ID:", error);
        throw error;
    }
}
async function convertStrToAddress(chain, token) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraTokenTypesV2::get_token_name_from_address",
                type_arguments: [],
                arguments: [chain.toString(), token.toString()]
            })
        });

        const body = await response.json();
        // Access result[0].data based on your provided JSON structure
        const addr = body.result?.[0];

        console.log("addr_token:",addr);
        return addr; // Returns 0, 1, 2, 3, or 4

    } catch (error) {
        console.error("Error converting chain string to ID:", error);
        throw error;
    }
}

async function convertVaultStrToAddress(provider, chain) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraProviderTypesV2::get_vault_by_name",
                type_arguments: [],
                arguments: [provider.toString(), chain.toString()]
            })
        });

        const body = await response.json();
        // Access result[0].data based on your provided JSON structure
        const addr = body.result?.[0];

        console.log("addr_token:",addr);
        return addr; // Returns 0, 1, 2, 3, or 4

    } catch (error) {
        console.error("Error converting chain string to ID:", error);
        throw error;
    }
}
async function convertVaultAddrToStr(provider, chain) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0xb5a924dde82fd1e3dd0d1c99e863ccce2732a0e0e80c338f8eb3a4cd7ae5aed4::QiaraProviderTypesV2::get_name_by_vault",
                type_arguments: [],
                arguments: [provider.toString(), chain.toString()]
            })
        });

        const body = await response.json();
        // Access result[0].data based on your provided JSON structure
        const addr = body.result?.[0];

        console.log("addr_token:",addr);
        return addr; // Returns 0, 1, 2, 3, or 4

    } catch (error) {
        console.error("Error converting chain string to ID:", error);
        throw error;
    }
}

const getFields = (ab, fieldNames) => {
    const results = {};

    fieldNames.forEach(name => {
        const index = ab.data_types.indexOf(name);
        if (index === -1) {
            results[name] = null;
            return;
        }

        const rawHex = ab.data[index];
        if (!rawHex || rawHex === '0x') {
            results[name] = "0";
            return;
        }

        const hex = rawHex.startsWith('0x') ? rawHex.slice(2) : rawHex;
        const buffer = Buffer.from(hex, 'hex');

        // 1. Handle Amount (Little Endian 64-bit unsigned integer)
        if (name === 'amount' || name === 'time') {
            // Read as 64-bit Little Endian
            try {
                results[name] = buffer.readBigUInt64LE(0).toString();
                return;
            } catch (e) {
                // Fallback for non-8-byte numbers
                results[name] = BigInt('0x' + hex).toString();
                return;
            }
        }

        // 2. Handle Prefixed Strings (L, M, B)
        const firstByte = buffer[0];
        if (firstByte === 0x4c || firstByte === 0x4d || firstByte === 0x42) {
            // These are ASCII strings starting after the prefix
            results[name] = buffer.slice(1).toString('utf8').replace(/\0/g, '');
            // If it's the receiver, we usually want it back in hex format
            if (name === 'receiver' && !results[name].startsWith('0x')) {
                results[name] = '0x' + results[name];
            }
            return;
        }

        // 3. Handle Pascal Strings (Length-prefixed)
        // Check if the first byte matches the remaining length
        if (firstByte > 0 && firstByte === buffer.length - 1) {
            const potentialString = buffer.slice(1).toString('utf8');
            // Ensure it's printable text
            if (/^[\x20-\x7E]+$/.test(potentialString)) {
                results[name] = potentialString;
                return;
            }
        }

        // 4. Default: All Zeros (like Nonce)
        if (buffer.every(b => b === 0)) {
            results[name] = "0";
            return;
        }

        // 5. Catch-all: Convert Hex to BigInt String
        results[name] = BigInt('0x' + hex).toString();
    });

    return results;
};

function addLengthPrefix(hexStr) {
    // Remove 0x if present
    const cleanHex = hexStr.startsWith('0x') ? hexStr.slice(2) : hexStr;
    
    // Calculate byte length (2 hex chars = 1 byte)
    const byteLength = cleanHex.length / 2;
    
    // Convert length to hex and pad to ensure it's at least 2 chars (1 byte)
    // Note: For lengths > 127, you'd need a full ULEB128 encoder, 
    // but for 32 bytes, '20' is sufficient.
    const lengthPrefix = byteLength.toString(16).padStart(2, '0');
    
    return '0x' + lengthPrefix + cleanHex;
}

async function getUserNonce(user) {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x2ac776b09a5a0d55b03be6328ac874bb8897b3978c3b4dc0905622fbef629833::QiaraNonceV1::return_user_nonce",
                type_arguments: [],
                arguments: [user.toString()]
            })
        });

        const body = await response.json();
        // Access result[0].data based on your provided JSON structure
        const addr = body.result?.[0];

        console.log("nonce:",addr);
        return addr; // Returns 0, 1, 2, 3, or 4

    } catch (error) {
        console.error("Error converting chain string to ID:", error);
        throw error;
    }
}

const extractCoinName = (typeString) => {
    if (!typeString || typeof typeString !== 'string') return "";
    
    const parts = typeString.split('::');
    return parts[parts.length - 1];
};

function split256BitValue(input) {
    if (!input) return { high: 0n, low: 0n };

    let hex;

    // Check if input is a Move Type (contains ::) or a standard String
    if (typeof input === 'string' && (input.includes('::') || isNaN(input) && !input.startsWith('0x'))) {
        // Convert ASCII string to Hex
        hex = Array.from(input)
            .map(c => c.charCodeAt(0).toString(16).padStart(2, '0'))
            .join('');
    } else {
        // It's a normal number or hex address
        hex = BigInt(input).toString(16);
    }

    // 2. Pad to 64 hex characters (256 bits)
    // Note: If your strings are longer than 32 chars, they will exceed 256 bits.
    const paddedHex = hex.padStart(64, '0');
    
    // 3. Slice into two 32-character hex strings (128 bits each)
    const highHex = paddedHex.slice(0, 32);
    const lowHex = paddedHex.slice(32);
    
    return {
        high: BigInt("0x" + highHex),
        low: BigInt("0x" + lowHex)
    };
}

/*Signing data: [
  19912496784753681823845346756073915851684985124092546276405483311486694047715n,
  6967508469463948985474942233649465336811417623034660619373533014606239012767n,
  132174294339333013904321148690198827411n,
  2460678849n,
  86726804259n,
  0n,
  151n,
  2n
] */

function extractEventData(event, requestedNames) {
    const results = {};
    console.log(event);
    requestedNames.forEach(name => {
        // Find the object in the "data" array where name matches
        const entry = event.event_data.find(item => item.name === name);
        
        // Return the value if found, otherwise null
        results[name] = entry ? entry.value : null;
    });

    return results;
}
function extractEventTypes(event, requestedNames) {
    // .map() creates a new array by looking up the type for each name in order
    return requestedNames.map(name => {
        const entry = event.data.find(item => item.name === name);
        
        // Return the type string (e.g., "u64"), or "string" as a safe fallback
        return entry ? entry.type : "string";
    });
}


function packSlot8(chainID, amount, outNewNonce) {
    const chainIdBI = BigInt(chainID);
    const amountBI = BigInt(amount);
    const nonceBI = BigInt(outNewNonce);

    // Perform the shifts to match the updated Circom:
    // chainID + (amount * 2^32) + (nonce * 2^96)
    const packed = chainIdBI 
        + (amountBI << 32n) 
        + (nonceBI << 96n);

    return packed.toString(); 
}

const strToField = (input) => {
    if (!input || input === "0") return 0n;
    
    let val;
    
    // 1. Handle actual numbers or BigInts passed in
    if (typeof input === 'number' || typeof input === 'bigint') {
        val = BigInt(input);
    } 
    // 2. Handle numeric strings (e.g., "25000")
    else if (typeof input === 'string' && /^\d+$/.test(input)) {
        val = BigInt(input);
    } 
    // 3. Handle Hex strings
    else if (typeof input === 'string' && input.startsWith('0x')) {
        val = BigInt(input);
    } 
    // 4. Handle Text strings (e.g., "QiaraTokens")
    else {
        val = BigInt("0x" + Buffer.from(input).toString("hex"));
    }

    const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
    return val % P;
};

const fieldToStr = (input) => {
    // 1. Ensure we are working with a BigInt
    const val = BigInt(input);
    
    if (val === 0n) return "0";

    // 2. Convert BigInt to Hex string
    let hex = val.toString(16);

    // 3. Ensure even length for Buffer (pad with 0 if necessary)
    if (hex.length % 2 !== 0) {
        hex = "0" + hex;
    }

    // 4. Convert Hex to Buffer
    const buffer = Buffer.from(hex, "hex");

    // 5. Check if it's likely a text string or just a number
    // We check if the bytes fall within the printable ASCII range (32-126)
    const isPrintable = buffer.every(byte => byte >= 32 && byte <= 126);

    if (isPrintable) {
        return buffer.toString("utf8");
    } else {
        // If it contains non-printable characters, it's probably just a number
        return val.toString();
    }
};

const fieldToValue = (input) => {
    // 1. If it's already a number or looks like a plain decimal string, keep it simple
    if (typeof input === 'number') return input.toString();
    if (typeof input === 'string' && /^\d+$/.test(input) && input.length < 15) {
        return input; 
    }

    const val = BigInt(input);
    if (val === 0n) return "0";

    let hex = val.toString(16);
    if (hex.length % 2 !== 0) hex = "0" + hex;
    
    const buffer = Buffer.from(hex, "hex");

    // 2. Refined Address Check
    // Addresses are usually exactly 20 bytes (40 hex chars)
    if (buffer.length === 20) {
        return "0x" + hex.toLowerCase();
    }

    // 3. Refined Text Check
    // We only treat it as text if it's clearly not a small number
    const textPart = buffer.length > 1 ? buffer.slice(1) : buffer;
    const isPrintable = textPart.length > 0 && textPart.every(byte => byte >= 32 && byte <= 126);

    // If it's printable AND long enough to likely be a string, not a number
    // We also check if the first byte (length prefix) matches the remaining length
    const seemsLikeEncodedText = isPrintable && (buffer[0] === textPart.length);

    if (seemsLikeEncodedText || (isPrintable && textPart.length > 4)) { 
        return textPart.toString("utf8");
    }

    // 4. Default: Return as decimal string
    return val.toString();
};

function convertLittleEndian(hex, type) {
    if (!hex || !hex.startsWith('0x')) return hex;
    
    let raw = hex.slice(2);
    
    if (type === 'string') {
        let decoded = Buffer.from(raw, 'hex').toString('utf8');
        /**
         * BCS strings have a length prefix. 
         * We slice(1) to remove the length byte (e.g., \u001a or \u0002).
         * We also use .trim() to catch any stray control characters.
         */
        return decoded.slice(1);
    }

    if (type === 'u64' || type === 'u128' || type === 'u256') {
        // Ensure even length for byte pairs
        if (raw.length % 2 !== 0) raw = '0' + raw;
        
        let bytes = raw.match(/.{1,2}/g);
        if (bytes) {
            let bigEndianHex = bytes.reverse().join('');
            return BigInt('0x' + bigEndianHex).toString();
        }
    }
    
    return hex; 
}

function nativeBcsDecode(hexValue, type) {
    if (!hexValue || !hexValue.startsWith('0x')) return hexValue;

    try {
        const bytes = Uint8Array.from(Buffer.from(hexValue.slice(2), 'hex'));
        const SDK = require('supra-l1-sdk-core');
        const typeLower = type.toLowerCase();
        
        let deserializer;
        if (SDK.BCS && SDK.BCS.Deserializer) {
            deserializer = new SDK.BCS.Deserializer(bytes);
        } else if (SDK.BcsDeserializer) {
            deserializer = new SDK.BcsDeserializer(bytes);
        } else {
            throw new Error("BCS Deserializer class not found in SDK");
        }

        // --- Handle vector<u8> specially (Move Bytes/String) ---
        // In Move, vector<u8> is often used for strings or raw byte arrays.
        if (typeLower === 'vector<u8>') {
            const decodedBytes = deserializer.deserializeBytes();
            // Try to return as a readable string, fallback to hex if it contains non-printable chars
            const strValue = Buffer.from(decodedBytes).toString('utf8');
            return /^[\x20-\x7E]*$/.test(strValue) ? strValue : '0x' + Buffer.from(decodedBytes).toString('hex');
        }

        // --- Handle General Vectors (vector<address>, vector<u64>, etc.) ---
        if (typeLower.startsWith('vector<')) {
            const length = deserializer.deserializeUleb128AsU32();
            const list = [];
            for (let i = 0; i < length; i++) {
                if (typeLower.includes('address')) {
                    const addrBytes = deserializer.deserializeFixedBytes(32);
                    list.push('0x' + Buffer.from(addrBytes).toString('hex'));
                } else if (typeLower.includes('u64')) {
                    list.push(deserializer.deserializeU64().toString());
                } else if (typeLower.includes('string')) {
                    list.push(deserializer.deserializeStr());
                }
            }
            return list;
        }

        // --- Handle Single Types ---
        switch (typeLower) {
            case 'string':
                return deserializer.deserializeStr();
            case 'u8':
                return deserializer.deserializeU8().toString();
            case 'u16':
                return deserializer.deserializeU16().toString();
            case 'u32':
                return deserializer.deserializeU32().toString();
            case 'u64':
                return deserializer.deserializeU64().toString();
            case 'u128':
                return deserializer.deserializeU128().toString();
            case 'u256':
                return deserializer.deserializeU256().toString();
            case 'address':
                const addrBytes = deserializer.deserializeFixedBytes(32);
                return '0x' + Buffer.from(addrBytes).toString('hex');
            default:
                return hexValue;
        }
    } catch (error) {
        console.warn(`Native decode failed for ${type}:`, error.message);
        return hexValue;
    }
}

function leHexToBI(hex) {
    // 1. Fast path: If it's already a BigInt or Number, return it immediately
    if (typeof hex === 'bigint') return hex;
    if (typeof hex === 'number') return BigInt(hex);
    
    // 2. Handle empty/null cases
    if (!hex || hex === '0x') return 0n;

    let cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
    
    // Ensure even length for byte pairs
    if (cleanHex.length % 2 !== 0) {
        cleanHex = '0' + cleanHex;
    }   

    // 3. Faster Little-Endian swap using a single loop
    let leHex = "";
    for (let i = cleanHex.length - 2; i >= 0; i -= 2) {
        leHex += cleanHex.slice(i, i + 2);
    }

    return BigInt("0x" + leHex);
}
//getValidatorConfig();
module.exports = { getFunctionData, getEventData,addLengthPrefix, getPrivKey,convertVaultStrToAddress, packSlot8, getFields, extractCoinName, loadGeneratedProof, convertVaultAddrToStr, getValidatorConfig, convertStrToAddress, getUserNonce, convertLittleEndian, convertTokenStrToAddress, strToField,leHexToBI, fieldToStr, extractEventTypes, fieldToValue, nativeBcsDecode, convertChainStrToID, split256BitValue, extractEventData  };