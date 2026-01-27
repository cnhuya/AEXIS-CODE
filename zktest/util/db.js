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
function storeBalances(apiResponse, chainName) {
  // Use a transaction for speed (very important for bulk blockchain data)
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
      for (const tokenEntry of userEntry.value.data) {
        insert.run(wallet, chainName, tokenEntry.key, tokenEntry.value);
      }
    }
  });

  runInsert(apiResponse.result[0].data);
  console.log(`Updated balances for ${chainName}`);
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

module.exports = {storeBalances,getBalances,updateUserBalance,getUserBalance};