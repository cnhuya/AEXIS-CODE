const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { getValidatorConfig } = require("../global_util.js");

const dbPath = path.resolve(__dirname, '../../database/events.db');
const dbDir = path.dirname(dbPath);
if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });

const db = new Database(dbPath);
db.pragma('journal_mode = WAL');

// --- TABLE SETUP ---
db.exec(`
  CREATE TABLE IF NOT EXISTS sync_state (
    category TEXT PRIMARY KEY, 
    cursor TEXT
  );

  CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,           -- 'consensus', 'crosschain', or 'validate'
    type_name TEXT,               -- Added: e.g., 'Request Bridge'
    transaction_hash TEXT NOT NULL UNIQUE,
    block_height INTEGER NOT NULL,
    identifier TEXT,              -- The unique hash from Move
    status TEXT DEFAULT 'pending', -- 'pending' or 'validated'
    event_data TEXT NOT NULL, 
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_events_type ON events (type);
  CREATE INDEX IF NOT EXISTS idx_events_type_name ON events (type_name); -- New index
  CREATE INDEX IF NOT EXISTS idx_events_identifier ON events (identifier);
`);

/**
 * Stores events, updates cursor, and enforces limits.
 */
function storeEvents(eventsArray, type, cursor) {
    const allowedTypes = ['consensus', 'crosschain', 'validate'];
    if (!allowedTypes.includes(type)) {
        throw new Error(`Invalid event type: ${type}`);
    }

    if (cursor) updateSavedCursor(type, cursor);

    const insertStmt = db.prepare(`
        INSERT OR IGNORE INTO events (type, type_name, transaction_hash, block_height, identifier, event_data)
        VALUES (?, ?, ?, ?, ?, ?)
    `);

    // Target a specific event type when validating
    const updateStatusStmt = db.prepare(`
        UPDATE events SET status = 'validated' WHERE identifier = ? AND type = ?
    `);

    const newlyInserted = db.transaction((events) => {
        let results = [];
        
        for (const item of events) {
            const dataMap = Object.fromEntries(item.data.map(f => [f.name, f.value]));
            const identifier = dataMap.identifier || null;
            const eventType = dataMap.event_type || null;

            // 2. MARK AS VALIDATED (The Chain Logic)
            if (identifier) {
                if (type === 'crosschain') {
                    // 1. Crosschain Event validates the original Consensus Event
                    const info = updateStatusStmt.run(identifier, 'consensus');
                    if (info.changes > 0) {
                        console.log(`✅ Consensus ${identifier} validated by Crosschain proof.`);
                    }
                } 
                else if (type === 'validate') {
                    // 2. Only Validation Events labeled "Proofs" validate the Crosschain Event
                    if (eventType === 'Proofs') {
                        const info = updateStatusStmt.run(identifier, 'crosschain');
                        if (info.changes > 0) {
                            console.log(`✅ Crosschain ${identifier} validated by formal Proof quorum.`);
                        }
                    } else {
                        // Standard Request Bridge validation (for the consensus event)
                        const info = updateStatusStmt.run(identifier, 'consensus');
                        if (info.changes > 0) {
                            console.log(`✅ Consensus ${identifier} validated by ${eventType} quorum.`);
                        }
                    }
                }
            }

            // 3. INSERT
            const info = insertStmt.run(
                type, 
                item.type_name || null, 
                item.tx_hash, 
                item.block, 
                identifier, 
                JSON.stringify(item.data)
            );

            if (info.changes > 0) {
                results.push(item);
            }
        }
        return results;
    })(eventsArray);

    if (newlyInserted.length > 0) enforceLimit(type);
    return newlyInserted; 
}

/**
 * Dynamic limit enforcement based on config
 */
function enforceLimit(type) {
    const config = getValidatorConfig();
    const limitKey = `${type.toUpperCase()}_EVENTS_MEMORY_LIMIT`;
    const limit = config[limitKey] || 1000;

    const countRow = db.prepare('SELECT COUNT(*) as total FROM events WHERE type = ?').get(type);
    
    if (countRow.total > limit) {
        const toDelete = countRow.total - limit;
        db.prepare(`
            DELETE FROM events WHERE id IN (
                SELECT id FROM events 
                WHERE type = ? 
                ORDER BY block_height ASC, id ASC 
                LIMIT ?
            )
        `).run(type, toDelete);
        console.log(`🧹 [${type}] Purged ${toDelete} old events.`);
    }
}

// --- HELPER FUNCTIONS ---

function getCursor(category) {
    const row = db.prepare('SELECT cursor FROM sync_state WHERE category = ?').get(category);
    return row ? row.cursor : null;
}

function updateSavedCursor(category, cursor) {
    db.prepare(`
        INSERT INTO sync_state (category, cursor) VALUES (?, ?)
        ON CONFLICT(category) DO UPDATE SET cursor = excluded.cursor
    `).run(category, cursor);
}

function isEventStored(txHash) {
    const row = db.prepare('SELECT 1 FROM events WHERE transaction_hash = ?').get(txHash);
    return !!row;
}

function getPendingEvents(type) {
    const rows = db.prepare(`
        SELECT * FROM events 
        WHERE type = ? AND status = 'pending' 
        ORDER BY block_height ASC
    `).all(type);
    
    return rows.map(r => ({
        ...r,
        event_data: JSON.parse(r.event_data)
    }));
}

function getEventsByType(type) {
    const rows = db.prepare('SELECT * FROM events WHERE type = ? ORDER BY block_height DESC').all(type);
    return rows.map(r => ({
        ...r,
        event_data: JSON.parse(r.event_data)
    }));
}

// --- EXPORTS ---
module.exports = { 
    storeEvents, 
    isEventStored, 
    getEventsByType, 
    getCursor, 
    updateSavedCursor,
    getPendingEvents
};