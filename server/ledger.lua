-- Vanguard Bank - account history. kinds: deposit, withdraw, transfer_in, transfer_out,
-- income, payment, refund, system.

Ledger = {}

local function clip(text, size)
    if type(text) ~= 'string' then return nil end
    return text:sub(1, size)
end

function Ledger.add(number, kind, amount, actor, note)
    MySQL.insert('INSERT INTO vbank_transactions (account, kind, amount, actor, note) VALUES (?, ?, ?, ?, ?)',
        { number, kind, amount, clip(actor, 60), clip(note, 80) })
end

--- Newest first; beforeId pages further back.
function Ledger.page(number, beforeId, limit)
    if beforeId then
        return MySQL.query.await(
            'SELECT id, kind, amount, actor, note, UNIX_TIMESTAMP(created_at) AS time FROM vbank_transactions WHERE account = ? AND id < ? ORDER BY id DESC LIMIT ?',
            { number, beforeId, limit }) or {}
    end
    return MySQL.query.await(
        'SELECT id, kind, amount, actor, note, UNIX_TIMESTAMP(created_at) AS time FROM vbank_transactions WHERE account = ? ORDER BY id DESC LIMIT ?',
        { number, limit }) or {}
end
