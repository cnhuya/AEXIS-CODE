// state.js


const state = {
    validators: { items: [], oldRoot: null, newRoot: null, sigs: [], epoch: 0 },
    variables: { items: [], oldRoot: null, newRoot: null, sigs: [] },
    balances: { items: [], oldRoot: null, newRoot: null, sigs: [] },
    relayer: {events: []}
};

/**
 * Updates specific fields in a namespace.
 */
const updateState = (namespace, partialData) => {
    if (!state[namespace]) state[namespace] = {};
    state[namespace] = { ...state[namespace], ...partialData };
};

/**
 * Retrieves data from the state.
 * @param {string} [namespace] - Optional: 'variables', 'accounts', etc.
 * @returns The requested namespace or the full state if no namespace is provided.
 */
const getState = (namespace) => {
    if (!namespace) return state; // Returns everything
    return state[namespace] || null; // Returns specific bucket or null if missing
};

module.exports = { updateState, getState };