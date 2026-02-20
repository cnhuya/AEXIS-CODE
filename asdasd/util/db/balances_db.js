const fs = require('fs');
const path = require('path');

const Database = require('better-sqlite3');

const dbPath = path.resolve(__dirname, '../database/balances.db');
const dbDir = path.dirname(dbPath);
if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });

const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
// 2. Create the table with a UNIQUE constraint
db.exec(`
  CREATE TABLE IF NOT EXISTS user_balances (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    walletAddress TEXT NOT NULL,
    chain TEXT NOT NULL,
    token TEXT NOT NULL,
    amount TEXT NOT NULL,
    updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(walletAddress, chain, token)
  )
`);

// 3. The storage function
function storeBalances(userDataArray) {
    const insert = db.prepare(`
        INSERT INTO user_balances (walletAddress, chain, token, amount, updatedAt)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(walletAddress, chain, token) DO UPDATE SET
            amount = excluded.amount,
            updatedAt = CURRENT_TIMESTAMP
    `);

    const runInsert = db.transaction((data) => {
        for (const userEntry of data) {
            const wallet = userEntry.key;

            // Iterate through the Chains (e.g., "Base")
            for (const chainEntry of userEntry.value.data) {
                const chainName = chainEntry.key; 

                // Iterate through the Tokens (e.g., "USDC")
                for (const tokenEntry of chainEntry.value.data) {
                    const tokenSymbol = tokenEntry.key;
                    const amount = tokenEntry.value;

                    insert.run(wallet, chainName, tokenSymbol, amount);
                }
            }
        }
    });

    runInsert(userDataArray);
    console.log(`✅ Processed ${userDataArray.length} wallets into DB.`);
}

// 4. Example Query: Get all users with USDT on Ethereum
function getBalances(chain, token) {
  const stmt = db.prepare('SELECT * FROM user_balances WHERE chain = ? AND token = ?');
  return stmt.all(chain, token);
}

// = USER FUNCTIONS = //
function updateUserBalance(walletAddress, chain, token, amount) {
    const stmt = db.prepare(`
        INSERT INTO user_balances (walletAddress, chain, token, amount, updatedAt)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(walletAddress, chain, token) DO UPDATE SET
            amount = excluded.amount,
            updatedAt = CURRENT_TIMESTAMP
    `);

    // .run() executes the prepared statement
    const info = stmt.run(walletAddress, chain, token, amount);
    
    return info.changes > 0; // Returns true if a row was affected
}   

function getUserBalance(walletAddress, chain, token) {
    const row = db.prepare(
        'SELECT amount FROM user_balances WHERE walletAddress = ? AND chain = ? AND token = ?'
    ).get(walletAddress, chain, token);
    
    return row ? row.amount : "0";
}

function getAllBalancesRaw() {
    const stmt = db.prepare('SELECT walletAddress, chain, token, amount, updatedAt FROM user_balances');
    return stmt.all();
}

module.exports = {storeBalances,getBalances,updateUserBalance,getUserBalance, getAllBalancesRaw};