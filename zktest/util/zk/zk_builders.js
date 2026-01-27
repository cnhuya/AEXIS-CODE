const { buildPoseidon, buildEddsa } = require("circomlibjs");

class PoseidonMerkleTree {
    constructor(leaves, poseidon, depth = 10) {
        this.poseidon = poseidon;
        const F = poseidon.F;
        this.depth = depth;
        
        // 1. Pad leaves to the full capacity of the tree (2^depth)
        // Use 0 as the default value for empty slots
        let fullLeaves = [...leaves];
        while (fullLeaves.length < Math.pow(2, depth)) {
            fullLeaves.push("0");
        }

        // 2. Hash leaves: Hash(index, value) to match Circom leafHasher
        // Inside constructor
        this.leaves = fullLeaves.map((v, i) => {
            // If it's a dummy leaf (padding), we use zeros
            if (v === "0") {
                return F.toObject(this.poseidon([0, 0, 0]));
            }
            // MUST match Circom leafHasher: Poseidon(pubKeyX, pubKeyY, stake)
            return F.toObject(this.poseidon([
                BigInt(v.pub_key_x), 
                BigInt(v.pub_key_y), 
                BigInt(v.staked)
            ]));
        });

        
        this.layers = []; 
        this.buildTree();
    }

    buildTree() {
        let currentLayer = this.leaves;
        this.layers.push(currentLayer);

        // Force the tree to climb to the specified depth
        for (let d = 0; d < this.depth; d++) {
            let nextLayer = [];
            for (let i = 0; i < currentLayer.length; i += 2) {
                const left = currentLayer[i];
                // In a perfectly padded tree, right will always exist
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

        // Iterate exactly 'depth' times
        for (let i = 0; i < this.depth; i++) {
            let layer = this.layers[i];
            let isRightNode = currentIndex % 2 === 1;
            let siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;

            siblings.push(layer[siblingIndex]);
            indices.push(isRightNode ? 1 : 0);

            currentIndex = Math.floor(currentIndex / 2);
        }

        return { siblings, indices };
    }

    getRoot() {
        return this.layers[this.layers.length - 1][0];
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
    // 1. Calculate leaves
    const leaves = validators.map(val => {
        // Ensure values are BigInts or strings
        return poseidon([val.pub_key_x, val.pub_key_y, val.staked]);
    });

    // 2. Pad leaves to the nearest power of 2 (e.g., 32 for depth 5)
    const nValidators = 8;
    while (leaves.length < nValidators) {
        // Use 0 as the "empty leaf" value
        leaves.push(poseidon.F.e("0"));
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
async function get_validators() {
    try {
        const response = await fetch('https://rpc-testnet.supra.com/rpc/v3/view', {
            method: 'POST',
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                function: "0x6341ca6cd563e9317718102d312a2281fbb9b3e4506b4871d98dab4085f94ec1::QiaraVv31::return_all_active_parents_full",
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
                address: v.key,
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

module.exports = {PoseidonMerkleTree, signRotationMessage, generateGenesisRoot, get_validators};