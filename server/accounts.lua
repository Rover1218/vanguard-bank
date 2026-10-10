-- Vanguard Bank - account store. Balances change only through Accounts.adjust (atomic, never below zero).

Accounts = {}

local RESOURCE = GetCurrentResourceName()
local NUMBER_TRIES = 20

local function normalise(row)
    if row then row.balance = tonumber(row.balance) or 0 end
    return row
end

function Accounts.newNumber()
    for _ = 1, NUMBER_TRIES do
        local number = Rules.newNumber(math.random)
        local taken = MySQL.scalar.await(
            'SELECT 1 FROM vbank_accounts WHERE number = ? UNION SELECT 1 FROM vbank_personal WHERE number = ?',
            { number, number })
        if not taken then return number end
    end
    error('no free account number found')
end

--- The Personal account number of a character (made on first use).
function Accounts.personalNumber(citizenid)
    local number = MySQL.scalar.await('SELECT number FROM vbank_personal WHERE citizenid = ?', { citizenid })
    if number then return number end
    MySQL.insert.await('INSERT IGNORE INTO vbank_personal (citizenid, number) VALUES (?, ?)', { citizenid, Accounts.newNumber() })
    return MySQL.scalar.await('SELECT number FROM vbank_personal WHERE citizenid = ?', { citizenid })
end

--- Any account by its number. Personal accounts come back as { type = 'personal', number, owner, name }.
function Accounts.byNumber(number)
    local row = MySQL.single.await('SELECT * FROM vbank_accounts WHERE number = ?', { number })
    if row then return normalise(row) end
    local citizenid = MySQL.scalar.await('SELECT citizenid FROM vbank_personal WHERE number = ?', { number })
    if citizenid then return { type = 'personal', number = number, owner = citizenid, name = 'Personal' } end
    return nil
end

function Accounts.byRef(accountType, ref)
    return normalise(MySQL.single.await('SELECT * FROM vbank_accounts WHERE type = ? AND ref = ?', { accountType, tostring(ref) }))
end

function Accounts.create(accountType, name, owner, ref, balance)
    local number = Accounts.newNumber()
    local id = MySQL.insert.await(
        'INSERT INTO vbank_accounts (number, type, name, owner, ref, balance) VALUES (?, ?, ?, ?, ?, ?)',
        { number, accountType, name, owner, ref ~= nil and tostring(ref) or nil, balance or 0 })
    return id and Accounts.byNumber(number) or nil
end

--- The business / job / gang account for ref, created when missing; a changed name is saved.
function Accounts.ensureRef(accountType, ref, name)
    local existing = Accounts.byRef(accountType, ref)
    if existing then
        if name and existing.name ~= name then
            MySQL.update.await('UPDATE vbank_accounts SET name = ? WHERE id = ?', { name, existing.id })
            existing.name = name
        end
        return existing
    end
    local ok, created = pcall(Accounts.create, accountType, name or tostring(ref), nil, ref, 0)
    return (ok and created) or Accounts.byRef(accountType, ref) -- made by someone else at the same moment
end

--- Adds delta (negative to take) unless the balance would go below zero. Never throws.
function Accounts.adjust(id, delta)
    local ok, changed = pcall(MySQL.update.await,
        'UPDATE vbank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? >= 0', { delta, id, delta })
    if not ok then
        print(('[%s] balance change of %d on account %s failed: %s'):format(RESOURCE, delta, tostring(id), tostring(changed)))
        return false
    end
    return changed == 1
end

function Accounts.ownedCount(citizenid)
    return MySQL.scalar.await("SELECT COUNT(*) FROM vbank_accounts WHERE owner = ? AND type IN ('savings', 'shared')", { citizenid }) or 0
end

function Accounts.owned(citizenid)
    local rows = MySQL.query.await("SELECT * FROM vbank_accounts WHERE owner = ? AND type IN ('savings', 'shared') ORDER BY id", { citizenid }) or {}
    for _, row in ipairs(rows) do normalise(row) end
    return rows
end

--- Shared accounts this character is a member of (not owner), each with .role.
function Accounts.memberships(citizenid)
    local rows = MySQL.query.await(
        'SELECT a.*, m.role FROM vbank_members m JOIN vbank_accounts a ON a.id = m.account_id WHERE m.citizenid = ? ORDER BY a.id',
        { citizenid }) or {}
    for _, row in ipairs(rows) do normalise(row) end
    return rows
end

function Accounts.roleOf(accountId, citizenid)
    return MySQL.scalar.await('SELECT role FROM vbank_members WHERE account_id = ? AND citizenid = ?', { accountId, citizenid })
end

function Accounts.members(accountId)
    return MySQL.query.await('SELECT citizenid, name, role FROM vbank_members WHERE account_id = ? ORDER BY name', { accountId }) or {}
end

function Accounts.setMember(accountId, citizenid, name, role)
    MySQL.query.await(
        'INSERT INTO vbank_members (account_id, citizenid, name, role) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE role = VALUES(role), name = VALUES(name)',
        { accountId, citizenid, name, role })
end

function Accounts.removeMember(accountId, citizenid)
    return MySQL.update.await('DELETE FROM vbank_members WHERE account_id = ? AND citizenid = ?', { accountId, citizenid }) == 1
end

function Accounts.rename(id, name)
    MySQL.update.await('UPDATE vbank_accounts SET name = ? WHERE id = ?', { name, id })
end

--- Deletes the account only while it is empty (members go with it). True when it was closed.
function Accounts.close(id)
    return MySQL.update.await('DELETE FROM vbank_accounts WHERE id = ? AND balance = 0', { id }) == 1
end
