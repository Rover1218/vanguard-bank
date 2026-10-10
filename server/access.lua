-- Vanguard Bank - who may do what with which account. Roles are worked out on every request, so a
-- fired manager, a demoted boss or a removed member loses access straight away.

Access = {}

local BUSINESS = 'vanguard-business'
local ACTIONS = { 'deposit', 'withdraw', 'transfer', 'manage' }

--- { [businessId] = { id, name, rank } } for businesses whose account this character may use.
local function businessRoles(citizenid)
    if GetResourceState(BUSINESS) ~= 'started' then return {} end
    local ok, roles = pcall(function() return exports[BUSINESS]:bankRoles(citizenid) end)
    if not ok or type(roles) ~= 'table' then return {} end
    local result = {}
    for _, entry in ipairs(roles) do
        if type(entry) == 'table' and type(entry.id) == 'number' and type(entry.rank) == 'number'
            and entry.rank >= Config.BusinessMinRank then
            result[entry.id] = entry
        end
    end
    return result
end

local function isBossOf(group, name)
    return group ~= nil and group.isBoss and group.name == name
end

function Access.roleOf(src, account)
    local citizenid = Bridge.citizenid(src)
    if not citizenid or not account then return nil end
    local accountType = account.type
    if accountType == 'personal' then return account.owner == citizenid and 'holder' or nil end
    if accountType == 'savings' or accountType == 'shared' then
        if account.owner == citizenid then return 'owner' end
        if accountType == 'shared' then return Accounts.roleOf(account.id, citizenid) end
        return nil
    end
    if accountType == 'business' then return businessRoles(citizenid)[tonumber(account.ref)] and 'boss' or nil end
    if accountType == 'job' then return isBossOf(Bridge.job(src), account.ref) and 'boss' or nil end
    if accountType == 'gang' then return isBossOf(Bridge.gang(src), account.ref) and 'boss' or nil end
    return nil
end

--- The account behind number if the caller may do action on it: account, role or nil, message.
function Access.check(src, number, action)
    local parsed = Rules.parseNumber(number)
    local account = parsed and Accounts.byNumber(parsed)
    if not account then return nil, 'That account does not exist' end
    local role = Access.roleOf(src, account)
    if not role then return nil, 'You do not have access to that account' end
    if not Rules.can(account.type, role, action) then return nil, 'Your role on this account does not allow that' end
    return account, role
end

--- Every account the character can see: Personal, owned, shared, business, job, gang.
function Access.list(src)
    local citizenid = Bridge.citizenid(src)
    local list = {}
    local function add(account, role) if account then list[#list + 1] = { account = account, role = role } end end

    add({ type = 'personal', number = Accounts.personalNumber(citizenid), owner = citizenid, name = 'Personal',
        balance = Bridge.money(src, 'bank') }, 'holder')
    for _, account in ipairs(Accounts.owned(citizenid)) do add(account, 'owner') end
    for _, account in ipairs(Accounts.memberships(citizenid)) do add(account, account.role) end

    local businesses = {}
    for id, entry in pairs(businessRoles(citizenid)) do businesses[#businesses + 1] = { id = id, name = entry.name } end
    table.sort(businesses, function(a, b) return a.id < b.id end)
    for _, business in ipairs(businesses) do add(Accounts.ensureRef('business', business.id, business.name), 'boss') end

    local job = Bridge.job(src)
    if job and job.isBoss then add(Accounts.ensureRef('job', job.name, job.label), 'boss') end
    local gang = Bridge.gang(src)
    if gang and gang.isBoss and gang.name ~= 'none' then add(Accounts.ensureRef('gang', gang.name, gang.label), 'boss') end
    return list
end

--- What the UI shows for one account (the server still re-checks every action).
function Access.view(entry)
    local account = entry.account
    local can = {}
    for _, action in ipairs(ACTIONS) do can[action] = Rules.can(account.type, entry.role, action) end
    return {
        number = account.number, type = account.type, name = account.name,
        balance = account.balance or 0, role = entry.role, can = can,
    }
end
