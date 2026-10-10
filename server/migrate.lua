-- Vanguard Bank - one-time copy of qb-banking's accounts. The flag is set before copying, so a
-- crash half-way never copies balances twice (check the console line if it ever stops early).

Migrate = {}

local RESOURCE = GetCurrentResourceName()

function Migrate.qbBanking()
    if Db.meta('migrated_qbbanking') then return end
    Db.setMeta('migrated_qbbanking', 'started')
    local exists = MySQL.scalar.await(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'bank_accounts'")
    if (exists or 0) == 0 then return Db.setMeta('migrated_qbbanking', 'no qb-banking table') end

    local copied = 0
    for _, row in ipairs(MySQL.query.await('SELECT citizenid, account_name, account_balance, account_type, users FROM bank_accounts') or {}) do
        local balance = math.max(0, math.floor(tonumber(row.account_balance) or 0))
        if row.account_type == 'job' or row.account_type == 'gang' then
            local label = row.account_type == 'job' and Bridge.jobLabel(row.account_name) or Bridge.gangLabel(row.account_name)
            local account = Accounts.ensureRef(row.account_type, row.account_name, label or row.account_name)
            if account and balance > 0 and Accounts.adjust(account.id, balance) then
                Ledger.add(account.number, 'system', balance, 'qb-banking', 'Moved from qb-banking')
            end
            copied = copied + 1
        elseif row.account_type == 'shared' and row.citizenid then
            local account = Accounts.create('shared', Rules.cleanText(row.account_name, 24) or 'Shared', row.citizenid, nil, balance)
            local ok, users = pcall(json.decode, row.users or '[]')
            for _, member in ipairs(account and ok and type(users) == 'table' and users or {}) do
                if type(member) == 'string' and member ~= row.citizenid then
                    Accounts.setMember(account.id, member, Bridge.nameOf(member) or member, 'member')
                end
            end
            copied = copied + 1
        end
    end
    Db.setMeta('migrated_qbbanking', ('copied %d'):format(copied))
    print(('[%s] copied %d account(s) from qb-banking'):format(RESOURCE, copied))
end
