const fs = require('fs');
const path = require('path');

async function getFunctionData(chain, actionName) {
    const functionsPath = path.join(__dirname, '../config/functions.json');
    const walletsPath = path.join(__dirname, '../config/wallets.json');

    const functionsData = JSON.parse(fs.readFileSync(functionsPath, 'utf8'));
    const walletsData = JSON.parse(fs.readFileSync(walletsPath, 'utf8'));

    const action = functionsData[chain]?.[actionName];
    if (!action) throw new Error(`Action ${actionName} not found for chain ${chain}`);

    const address = walletsData[chain][action.address_ref];

    // Check if it's an EVM chain (Base, Ethereum, etc.)
    if (chain !== "sui" && chain !== "supra") {
        let functionName;
        let abiArray;

        if (typeof action.contract_abi === 'object' && action.contract_abi !== null) {
            // It's a standard JSON ABI object
        } else if (typeof action.contract_abi === 'string' && action.contract_abi.includes('function')) {
            // It's a Human-Readable string
            const match = action.contract_abi.match(/function\s+(\w+)/);
            if (!match) throw new Error(`Could not extract function name from ABI string for ${actionName}`);
        } else {
            throw new Error(`Invalid or empty contract_abi for action ${actionName} on chain ${chain}`);
        }
        return {contract_address: address, abi: [action.contract_abi], functionName: action.contract_abi.name};
    }
    if(chain === "sui"){
        return {package: action.package, module_name: action.module_name, function_name: action.function_name, args: action.args};
    }
    if(chain === "supra"){
       return {module_address: address, module_name: action.module_name, function_name: action.function_name, args: action.args};
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
        // Return [Address, Single-Function ABI, Function Name extracted from ABI]
        // We extract the name so Ethers knows which one to call
        const functionName = action.contract_abi.match(/function\s+(\w+)/)[1];
        return [action.contract_abi, functionName];
    }

    // Return for Sui/Supra
    return  {event: action.event};
}

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

module.exports = { getFunctionData, getEventData, getPrivKey, getValidatorConfig };