-- Vanguard Bank - qb-banking compatibility. fxmanifest says provide 'qb-banking', so scripts written
-- for qb-banking (police fines, EMS, taxi, vehicle shop, houses, ps_lib) reach these exports unchanged.

local function society(name, create)
    if type(name) ~= 'string' or name == '' then return nil end
    local account = Accounts.byRef('job', name) or Accounts.byRef('gang', name)
    if account or not create then return account end
    if Bridge.isJob(name) then return Accounts.ensureRef('job', name, Bridge.jobLabel(name)) end
    if Bridge.isGang(name) then return Accounts.ensureRef('gang', name, Bridge.gangLabel(name)) end
    return nil
end

local function wholeDollars(amount)
    local value = math.floor(tonumber(amount) or 0)
    return Rules.wholeAmount(value, Config.MaxAmount)
end

local function caller() return GetInvokingResource() or 'server' end

local function addMoney(name, amount, reason)
    local value, account = wholeDollars(amount), society(name, true)
    if not value or not account or not Accounts.adjust(account.id, value) then return false end
    Ledger.add(account.number, 'income', value, caller(), reason)
    return true
end

local function removeMoney(name, amount, reason)
    local value, account = wholeDollars(amount), society(name, false)
    if not value or not account or not Accounts.adjust(account.id, -value) then return false end
    Ledger.add(account.number, 'payment', -value, caller(), reason)
    return true
end

local function getAccount(name)
    local account = society(name, false)
    if not account then return nil end
    return { id = account.id, account_name = name, account_balance = account.balance, account_type = account.type, users = '[]' }
end

local function getBalance(name)
    local account = society(name, false)
    return account and account.balance or 0
end

local function createSociety(accountType)
    return function(name, balance)
        if type(name) ~= 'string' or name == '' then return false end
        local existing = Accounts.byRef(accountType, name)
        local label = (accountType == 'job' and Bridge.jobLabel(name) or Bridge.gangLabel(name)) or name
        local account = existing or Accounts.ensureRef(accountType, name, label)
        local value = wholeDollars(balance)
        if not existing and account and value then Accounts.adjust(account.id, value) end
        return account and account.id or false
    end
end

local function createPlayerAccount(playerId, accountName, accountBalance, accountUsers)
    local citizenid = Bridge.citizenid(playerId)
    local name = Rules.cleanText(accountName, 24)
    if not citizenid or not name then return false end
    local account = Accounts.create('shared', name, citizenid, nil, wholeDollars(accountBalance) or 0)
    if not account then return false end
    local ok, users = pcall(json.decode, accountUsers or '[]')
    for _, member in ipairs(ok and type(users) == 'table' and users or {}) do
        if type(member) == 'string' and member ~= citizenid then
            Accounts.setMember(account.id, member, Bridge.nameOf(member) or member, 'member')
        end
    end
    return account.id
end

local function createBankStatement(playerId, accountName, amount, reason, statementType, accountType)
    local value = wholeDollars(amount)
    if not value then return false end
    local number
    if accountType == 'player' or accountName == 'checking' then
        local citizenid = Bridge.citizenid(playerId)
        number = citizenid and Accounts.personalNumber(citizenid)
    else
        local account = society(accountName, false)
        number = account and account.number
    end
    if not number then return false end
    local deposit = statementType == 'deposit'
    Ledger.add(number, deposit and 'income' or 'payment', deposit and value or -value, caller(), reason)
    return true
end

exports('AddMoney', addMoney)
exports('AddGangMoney', addMoney)
exports('RemoveMoney', removeMoney)
exports('RemoveGangMoney', removeMoney)
exports('GetAccount', getAccount)
exports('GetGangAccount', getAccount)
exports('GetAccountBalance', getBalance)
exports('GetBalance', getBalance)
exports('CreateJobAccount', createSociety('job'))
exports('CreateGangAccount', createSociety('gang'))
exports('CreatePlayerAccount', createPlayerAccount)
exports('CreateBankStatement', createBankStatement)
