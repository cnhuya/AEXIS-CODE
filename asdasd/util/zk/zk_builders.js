const { buildPoseidon, buildEddsa } = require("circomlibjs");
const { ethers } = require("ethers"); // Keccak256 is standard, or use crypto
const { strToField, split256BitValue, convertChainStrToID, extractEventData, getUserNonce, convertTokenStrToAddress} = require("../global_util.js");
/*class PoseidonMerkleTree {
    constructor(leaves, poseidon, depth = 10, type = "validators") {
        this.poseidon = poseidon;
        this.depth = depth;
        this.type = type; 
        const F = poseidon.F;

        // Configuration for how to hash a RAW object into a leaf
        this.configs = {
            validators: (v) => [
                BigInt(v.pub_key_x || 0),
                BigInt(v.pub_key_y || 0),
                BigInt(v.staked || 0)
            ],
            balances: (v) => [
                BigInt(v.userAddress_L || 0),
                BigInt(v.userAddress_H || 0),
                BigInt(v.balance || 0),
                BigInt(v.storageID_L || 0),
                BigInt(v.storageID_H || 0)
            ],
            // It MUST look like this to match Circom:
            variables: (v) => [
                strToField(v.header), 
                strToField(v.name), 
                BigInt(v.data) // <-- Treat data as a NUMBER, not a string field
            ]
        };

        const capacity = Math.pow(2, depth);
        
        this.leaves = Array.from({ length: capacity }, (_, i) => {
            const v = leaves[i];
            
            // 1. If slot is empty, we MUST hash [0,0,0] to match your old working version
            if (!v || v === "0") {
                return F.toObject(this.poseidon([0n, 0n, 0n]));
            }

            // 2. If it's already a hashed value (BigInt or hex string), use it
            if (typeof v === 'bigint' || (typeof v === 'string' && v.length > 30)) {
                return BigInt(v);
            }

            // 3. If it's a raw object, hash it using the config
            return F.toObject(this.poseidon(this.configs[type](v)));
        });

        this.layers = [];
        this.buildTree();
    }

    update(index, newLeaf) {
        this.leaves[index] = this.poseidon.F.toObject(newLeaf);
        let currentIndex = index;
        
        // Re-hash the path from the leaf to the root
        for (let i = 0; i < this.depth; i++) {
            let layer = this.layers[i];
            let isRightNode = currentIndex % 2 === 1;
            let siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;
            
            let left = isRightNode ? layer[siblingIndex] : layer[currentIndex];
            let right = isRightNode ? layer[currentIndex] : layer[siblingIndex];
            
            let hash = this.poseidon.F.toObject(this.poseidon([left, right]));
            
            currentIndex = Math.floor(currentIndex / 2);
            this.layers[i + 1][currentIndex] = hash;
        }
    }

    buildTree() {
        let currentLayer = this.leaves;
        this.layers = [currentLayer];

        for (let d = 0; d < this.depth; d++) {
            let nextLayer = [];
            for (let i = 0; i < currentLayer.length; i += 2) {
                const left = currentLayer[i];
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
        for (let i = 0; i < this.depth; i++) {
            let layer = this.layers[i];
            let isRightNode = currentIndex % 2 === 1;
            let siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;
            siblings.push(layer[siblingIndex].toString());
            indices.push(isRightNode ? 1 : 0);
            currentIndex = Math.floor(currentIndex / 2);
        }
        return { siblings, indices };
    }

    getRoot() {
        return this.layers[this.layers.length - 1][0];
    }
} */

/* */

class PoseidonMerkleTree {
    constructor(initialLeaves = [], poseidon, depth = 256, type = "validators") {
        this.poseidon = poseidon;
        this.depth = depth;
        this.type = type;
        const F = poseidon.F;

        this.configs = {
            validators: (v) => [BigInt(v.pub_key_x || 0), BigInt(v.pub_key_y || 0)],
            balances: (v) => [
                BigInt(v.userAddress_L || 0), 
                BigInt(v.userAddress_H || 0), 
                BigInt(v.balance || 0), 
                BigInt(v.storageID || 0), // Single value now!
                BigInt(v.nonce || 0)
            ],
            variables: (v) => [
                    strToField(v.header || ""), 
                    strToField(v.name || ""), 
                    BigInt(v.value || 0n)
                ]
        };

        // 1. Pre-calculate default hashes for empty nodes

        const leafInputLength = this.configs[type]({}).length; 
        const emptyLeafInputs = new Array(leafInputLength).fill(0n);
        
        this.zeroHashes = new Array(depth + 1);
        this.zeroHashes[0] = F.toObject(this.poseidon(emptyLeafInputs));


        for (let i = 1; i <= depth; i++) {
            this.zeroHashes[i] = F.toObject(this.poseidon([this.zeroHashes[i-1], this.zeroHashes[i-1]]));
        }

        // 2. Initialize the node cache (Level -> Index -> Value)
        this.nodes = new Array(depth + 1).fill(null).map(() => new Map());

        // 3. Populate initial data
        initialLeaves.forEach((v, index) => {
            if (v && v !== "0") {
                const leafValue = F.toObject(this.poseidon(this.configs[type](v)));
                this.nodes[0].set(BigInt(index), leafValue);
            }
        });

        // Build the initial tree state
        this._calculateAllLevels();
    }

    // Returns a leaf at a specific index, or the default zero leaf
    _getLeaf(index) {
        const idx = BigInt(index);
        return this.nodes[0].has(idx) ? this.nodes[0].get(idx) : this.zeroHashes[0];
    }

        // Update a single leaf and refresh the tree levels
    update(index, newLeafValue) {
        const F = this.poseidon.F;
        let currentIndex = BigInt(index);
        
        // 1. Hash the new leaf and store it
        let currentHash = (typeof newLeafValue === 'bigint') 
            ? newLeafValue 
            : F.toObject(newLeafValue);
        
        this.nodes[0].set(currentIndex, currentHash);

        // 2. Climb the tree to the root (Logarithmic update)
        for (let i = 0; i < this.depth; i++) {
            let isRight = (currentIndex % 2n === 1n);
            let siblingIndex = isRight ? currentIndex - 1n : currentIndex + 1n;
            let parentIndex = currentIndex / 2n;

            // Get sibling from cache or use pre-calculated zero hash
            let siblingValue = this.nodes[i].has(siblingIndex) 
                ? this.nodes[i].get(siblingIndex) 
                : this.zeroHashes[i];

            let left = isRight ? siblingValue : currentHash;
            let right = isRight ? currentHash : siblingValue;

            // Hash pair and move up
            currentHash = F.toObject(this.poseidon([left, right]));
            
            // Update the cache for the next level
            this.nodes[i + 1].set(parentIndex, currentHash);
            currentIndex = parentIndex;
        }

        return currentHash; // This is the new root
    }

    getRoot() {
        return this.nodes[this.depth].get(0n) || this.zeroHashes[this.depth];
    }

    // Replaces the slow recursive _getNodeAtLevel with a fast cache lookup
    _calculateAllLevels() {
        for (let i = 0; i < this.depth; i++) {
            const currentLevel = this.nodes[i];
            const nextLevel = this.nodes[i + 1];
            nextLevel.clear(); // Clear old branch data to prevent stale roots

            for (let [index, value] of currentLevel) {
                let parentIndex = index / 2n;
                if (nextLevel.has(parentIndex)) continue;

                let isRight = (index % 2n === 1n);
                let siblingIndex = isRight ? index - 1n : index + 1n;
                
                let siblingValue = currentLevel.has(siblingIndex) 
                    ? currentLevel.get(siblingIndex) 
                    : this.zeroHashes[i];

                let left = isRight ? siblingValue : value;
                let right = isRight ? value : siblingValue;
                
                const hash = this.poseidon([left, right]);
                nextLevel.set(parentIndex, this.poseidon.F.toObject(hash));
            }
        }
    }
    serialize() {
        // We only need to save the leaves (level 0) and basic config.
        // The rest can be re-calculated or is too heavy to send.
        return {
            depth: this.depth,
            type: this.type,
            // Convert Map of BigInts to a plain Object of Strings
            leaves: Object.fromEntries(
                Array.from(this.nodes[0].entries()).map(([k, v]) => [k.toString(), v.toString()])
            )
        };
    }

    generateProof(index) {
        let siblings = [];
        let indices = [];
        let currentIndex = BigInt(index);

        for (let i = 0; i < this.depth; i++) {
            let isRightNode = (currentIndex % 2n === 1n);
            let siblingIndex = isRightNode ? currentIndex - 1n : currentIndex + 1n;
            
            // Direct cache lookup (Instant even at depth 256)
            let siblingValue = this.nodes[i].has(siblingIndex)
                ? this.nodes[i].get(siblingIndex)
                : this.zeroHashes[i];
            
            siblings.push(siblingValue.toString());
            indices.push(isRightNode ? 1 : 0);
            currentIndex = currentIndex / 2n;
        }
        return { siblings, indices };
    }
    static async deserialize(data, poseidon) {
        // 1. Create a new instance
        const tree = new PoseidonMerkleTree([], poseidon, data.depth, data.type);
        
        // 2. Re-populate level 0 Map from the serialized entries
        for (const [idxStr, valStr] of Object.entries(data.leaves)) {
            tree.nodes[0].set(BigInt(idxStr), BigInt(valStr));
        }
        
        // 3. Re-calculate all levels (hashes) inside the worker
        tree._calculateAllLevels();
        
        return tree;
    }

}

class ProtocolState {
    constructor(balanceTree, validatorTree, variablesTree) {
        this.balanceTree = balanceTree;     // PoseidonMerkleTree (depth 256)
        this.validatorTree = validatorTree; // PoseidonMerkleTree (depth 4)
        this.variablesTree = variablesTree; // PoseidonMerkleTree (depth 256)
        this.poseidon = balanceTree.poseidon;
    }
/**
     * Updates a global variable (e.g., feeRate, totalVolume)
     */
    updateVariable(keyString, newValue) {
        const keyHash = strToField(keyString);
        const index = keyHash % BigInt(2 ** this.variablesTree.depth);
        
        const leafValue = this.poseidon.F.toObject(this.poseidon([
            keyHash, 
            BigInt(newValue)
        ]));

        this.variablesTree.update(index, leafValue);
        return {
            root: this.variablesTree.getRoot().toString(),
            proof: this.variablesTree.generateProof(index)
        };
    }
    /**
     * Handles the logic of a user spending/receiving.
     * Captures the state before and after.
     */
    async applyTransaction(eventItem) {
        const F = this.poseidon.F;
        const x = extractEventData(eventItem, ["addr", "token", "chain", "additional_outflow", "total_outflow"]);
        
        const userAddress = split256BitValue(x.addr);
        const storageID = strToField(x.token);
        const chainID = await convertChainStrToID(x.chain);

        // 1. Determine Position
        const index = await generateIndex([userAddress.low, userAddress.high, storageID, chainID], 256);

        // 2. GET CURRENT STATE (Before update)
        const oldBalance = BigInt(x.total_outflow || 0n);
        const oldNonce = BigInt(await getUserNonce(x.addr) || 0n);
        const oldRoot = this.balanceTree.getRoot().toString();
        
        // Generate the membership proof for the "Old" state
        const proof = this.balanceTree.generateProof(index);

        // 3. CALCULATE NEW STATE
        const newBalance = oldBalance + BigInt(x.additional_outflow);
        const newNonce = oldNonce + 1n;
        
        const finalLeaf = F.toObject(this.poseidon([
            userAddress.low, 
            userAddress.high, 
            newBalance, 
            storageID, 
            newNonce
        ]));

        // 4. COMMIT TO TREE
        this.balanceTree.update(index, finalLeaf);
        const newRoot = this.balanceTree.getRoot().toString();

        return {
            // State Roots
            oldAccountRoot: oldRoot,
            newAccountRoot: newRoot,
            currentValidatorRoot: this.validatorTree.getRoot().toString(),
            
            // Proof & Indices
            accountPathElements: proof.siblings,
            accountPathIndices: proof.indices,
            
            // Transaction Data (for circuit inputs)
            userAddress_L: userAddress.low.toString(),
            userAddress_H: userAddress.high.toString(),
            storageID: storageID.toString(),
            chainID: chainID.toString(),
            amount: x.additional_outflow.toString(),
            oldBalance: oldBalance.toString(),
            oldNonce: oldNonce.toString()
        };
    }

    /**
     * Handles Validator Set Updates
     */
    setValidators(newValidators) {
        const CIRCUIT_N_VALIDATORS = 16;
        const CIRCUIT_TREE_DEPTH = 4;

        // Map them into the format expected by your Tree Config
        const formatted = newValidators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
            pub_key_x: v.pub_key_x,
            pub_key_y: v.pub_key_y
        }));

        // Rebuild the validator tree
        this.validatorTree = new PoseidonMerkleTree(
            formatted, 
            this.poseidon, 
            CIRCUIT_TREE_DEPTH, 
            "validators"
        );
    }
}

async function prepare_leaves(type) {
    let poseidon = await buildPoseidon();
    
    if (type === "balances") {
        const accounts = await getAllBalancesRaw(); 
        // 1. Start with an empty tree
        const tree = new PoseidonMerkleTree([], poseidon, 256, "balances");

        for (const acc of accounts) {
            const splitAddr = split256BitValue(acc.walletAddress);
            const storageID = strToField(acc.token);
            
            // 2. Find the REAL index based on the address (Matching your circuit logic)
            const index = await generateIndex([splitAddr.low, splitAddr.high, storageID], 256);
            
            // 3. Prepare the leaf data
            const leafData = {
                userAddress_L: splitAddr.low,
                userAddress_H: splitAddr.high,
                balance: BigInt(acc.amount),
                storageID: storageID,
                nonce: BigInt(await getUserNonce(acc.walletAddress) || 0n)
            };

            // 4. Use your class's hashing config to get the value
            const leafValue = poseidon.F.toObject(poseidon(tree.configs.balances(leafData)));

            // 5. Place it at the specific sparse index
            tree.nodes[0].set(BigInt(index), leafValue);
        }

        // 6. Calculate the root once at the end (much faster than updating 256 levels every time)
        tree._calculateAllLevels();
        return tree;
    }

    if (type === "validators") {
        let validators = await get_validators();
        // Sequential is fine here!
        return new PoseidonMerkleTree(validators, poseidon, 4, "validators");
    }

    if (type === "variables") {
        const storedVars = await getAllStoredVariables(); // Fetch from your DB
        const tree = new PoseidonMerkleTree([], poseidon, 64, "variables");

        for (const v of storedVars) {
            // Use the index stored in your DB
            const index = BigInt(v.index); 
            
            // Generate the leaf value using the config
            const leafValue = poseidon.F.toObject(
                poseidon(tree.configs.variables({
                    header: v.header,
                    name: v.name,
                    value: v.value // This is the 'NewData' from your previous function
                }))
            );

            tree.nodes[0].set(index, leafValue);
        }
        tree._calculateAllLevels();
        return tree;
    }
}


    async function generateIndex(array, power) {
        let poseidon = await buildPoseidon();
        const F = poseidon.F; // Access the Finite Field helper
        // 1. Run the hash
        const hash = poseidon([...array]);
        
        // 2. Convert the hash result to a BigInt object
        const hashAsBigInt = F.toObject(hash);
        
        // 3. Apply the power-of-two mask
        return hashAsBigInt % (2n ** BigInt(power));
    }

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
        const babyPrivKeyHex = ethers.utils.keccak256(sigBytes.toString('hex')).slice(2);
        
        // 6. Convert hex string to Buffer for BabyJubJub
        let babyPrivKey = Buffer.from(babyPrivKeyHex.slice(2), "hex");

        const pubKey = eddsa.prv2pub(babyPrivKey);
        return {
            privKey: babyPrivKey,
            pubKeyX: eddsa.F.toObject(pubKey[0]).toString(),
            pubKeyY: eddsa.F.toObject(pubKey[1]).toString(),
        }

    }
async function signRotationMessage(babyPrivKey, data) {
    console.log("Signing data:", ...data);
    const eddsa = await buildEddsa();
    const poseidon = await buildPoseidon();

    // 1. Prepare the Message Hash
    const msgHash = poseidon([
        ...data
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

async function generateGenesisRoot(validators) {
    const poseidon = await buildPoseidon();
    const leaves = validators.map(val => {
        return poseidon([val.pub_key_x, val.pub_key_y, val.staked]);
    });

    // FIX 1: Use 16 to match your new Depth 4 circuit
    const nValidators = 16; 
    
    while (leaves.length < nValidators) {
        // FIX 2: Hash (0,0,0) to match the leafHasher[i] = Poseidon(3) in Circom
        leaves.push(poseidon([0, 0, 0])); 
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

async function generateGenericRoot(leaves, treeDepth) {
    const poseidon = await buildPoseidon();
    const F = poseidon.F;

    // 1. Ensure all leaves are Field Elements
    // We don't hash them here because prepareVariableLeaves already did it
    let currentLevel = leaves.map(leaf => (typeof leaf === "bigint" ? F.e(leaf) : leaf));

    // 2. Pad to full Tree Depth (2^depth)
    const totalLeaves = Math.pow(2, treeDepth);
    while (currentLevel.length < totalLeaves) {
        currentLevel.push(F.e("0"));
    }

    // 3. Build Tree (Hash Pairs)
    while (currentLevel.length > 1) {
        let nextLevel = [];
        for (let i = 0; i < currentLevel.length; i += 2) {
            // Internal nodes ALWAYS use Poseidon(2)
            nextLevel.push(poseidon([currentLevel[i], currentLevel[i + 1]]));
        }
        currentLevel = nextLevel;
    }

    return F.toObject(currentLevel[0]).toString();
}


// deprecated?
async function prepareValidators(newValidators, oldValidators){
    const poseidon = await buildPoseidon();
    const CIRCUIT_N_VALIDATORS = 16; 
    const CIRCUIT_TREE_DEPTH = 4;   

    // 1. Build Old Validator Tree
    const oldValidatorsForTree = oldValidators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
        pub_key_x: BigInt(v.pub_key_x),
        pub_key_y: BigInt(v.pub_key_y),
    }));
    const oldValTree = new PoseidonMerkleTree(oldValidatorsForTree, poseidon, CIRCUIT_TREE_DEPTH, "validators");

    // 2. Build New Validator Tree
     const newValidatorsForTree = newValidators.slice(0, CIRCUIT_N_VALIDATORS).map(v => ({
        pub_key_x: BigInt(v.pub_key_x),
        pub_key_y: BigInt(v.pub_key_y),
    }));
    const newValTree = new PoseidonMerkleTree(newValidatorsForTree, poseidon, CIRCUIT_TREE_DEPTH, "validators");

    return {tree: newValTree, newValRoot: newValTree.getRoot(), oldValRoot: oldValTree.getRoot()};
}

async function prepareVariables(tree, eventItem, poseidon) {
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
// deprecated
async function prepareBalances(tree, eventItem, poseidon) {
    const F = poseidon.F;

    // 1. Extract and format data from eventItem
    const x = extractEventData(eventItem, ["addr", "token", "chain", "additional_outflow", "total_outflow"]);
    console.log(x);
    const userAddress = split256BitValue(x.addr);
    let storageID = strToField(x.token);
    const chainID = await convertChainStrToID(x.chain);


    // 2. Generate the deterministic Index (matching your 256 depth)
    const index = await generateIndex([userAddress.low, userAddress.high, storageID, chainID], 256);


    // 3. Define the "Before" state (Old Balance)
    // Leaf = Poseidon(userL, userH, balance, storageL, storageH)
    const oldBalance = BigInt(x.total_outflow || 0n);
    const oldNonce = BigInt(await getUserNonce(x.addr) || 0n);
    console.log(userAddress, storageID, oldBalance);
    const oldLeaf = F.toObject(poseidon([
        userAddress.low, 
        userAddress.high, 
        oldBalance, 
        storageID, 
        oldNonce
    ]));
    console.log(index, oldLeaf);
    // Sync the tree to ensure the "Before" state is correct
    tree.update(index, oldLeaf);
    const oldRootForProof = tree.getRoot();

    // 4. Calculate the "After" state (New Balance)
    // Ensure both are BigInts before adding
    const additional = BigInt(x.additional_outflow || 0n);
    const current = BigInt(oldBalance || 0n);
    const newBalance = additional + current;
    const newNonce = oldNonce + 1n;
/*OLD ROOT: 19912496784753681823845346756073915851684985124092546276405483311486694047715
NEW ROOT: 6967508469463948985474942233649465336811417623034660619373533014606239012767 */
    const finalLeaf = F.toObject(poseidon([
        userAddress.low, 
        userAddress.high, 
        newBalance, 
        storageID, 
        newNonce
    ]));

    // 5. Update the tree to the "After" state
    tree.update(index, finalLeaf);
    const newRootForProof = tree.getRoot();

    console.log("OLD ROOT:", oldRootForProof.toString());
    console.log("NEW ROOT:", newRootForProof.toString());

    console.log(`[Tree] Slot ${index} updated. Balance: ${oldBalance} -> ${newBalance}`);

    return {
        oldRoot: oldRootForProof.toString(),
        newRoot: newRootForProof.toString(),
        index: index.toString(),
        newleaf: finalLeaf.toString(),
        newBalance: newBalance.toString(),
        oldBalance: oldBalance.toString(),
        newNonce: newNonce.toString()
    };
}

module.exports = {PoseidonMerkleTree, ProtocolState, prepare_leaves, signRotationMessage, generateGenesisRoot, deriveBabyJubKey, generateGenericRoot, prepareValidators, prepareVariables, prepareBalances, generateIndex};